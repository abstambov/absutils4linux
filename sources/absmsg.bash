#!/bin/bash

# absmsg.bash   version 0.1, © 2024 by Sergey Vasiliev aka abs.
# absmsg.bash - скрипт для упрощенной одновременной отправки сообщений по электронной почте, СМС и в системный журнал. Текст сообщения берётся из стандартного потока stdin и содержимого файлов - аргументов командной строки. Все не разобранные опции считаются именами файлов, которые последовательно добавляются к итоговому сообщению. Если сообщение вообще не задано, то в сообщение записывается имя текущего пользователя, имя хоста, время и дата.
# 
# absmsg.bash comes with ABSOLUTELY NO WARRANTY. This is free software, and you are welcome to redistribute it under certain conditions.  See  the GNU General Public Licence for details.
# 
# Использование: absmsg.bash [ОПЦИЯ] [--] [FILE1] [FILE2] ...
# 
# Опции:
# -e, --email                        отправить сообщение по электронной почте
# -j, --subject "Тема письма"        тема письма; по-умолчанию используется имя скрипта 'absmsg.bash'; опция игнорируется при выборе способа отправки сообщений sms
# -a, --attach "Имя файла"           вложение к письму: имя файла с путём; опция может быть использована многократно; опция игнорируется при выборе других способов отправки сообщений
# 
# -l, --log                          сделать запись в системном журнале
# -j, --subject "Тег"                тег записи в системном журнале; пробелы принудительно меняются на знаки подчёркивания '_'; если тег не задан, то используется имя скрипта 'absmsg.bash'; опция игнорируется при выборе способа отправки сообщений sms
# -p, --priority "facility.level"    описание возможных комбинаций имён facility и level смотрите 'man logger'; по-умолчанию используется user.info; опция игнорируется при выборе других способов отправки сообщений
# 
# -s, --sms                          отправить СМС
# 
# -c, --credentials "Имя файла"      путь к файлу с приватными данными для отправки сообщений по электронной почте и СМС; по умолчанию - ~/.absmsg-credentials
# -d, --debug                        режим отладки для вывода диагностических сообщений используемых команд
# -h, --help                         показывает эту подсказку
# 
# Примеры использования:
# echo "Сообщение" | absmsg.bash --log --email
# cat /etc/passwd | absmsg.bash --email --subject "Файл passwd"
# absmsg.bash --email --subject "Файл passwd" </etc/passwd
# echo "Сообщение" | absmsg.bash --log --email --subject "Письмо с вложениями" --attach "/etc/passwd" --attach /etc/group -d
# echo "Сообщение" | absmsg.bash --log --subject "Какой-то заголовок" --priority cron.err
# echo "Сообщение" | absmsg.bash -e -j "Какой-то заголовок" -d ~/.nanorc ~/.bashrc
# absmsg.bash -e -j "Какой-то заголовок" -- ~/.nanorc ~/.bashrc
# absmsg.bash -el
# echo "Сообщение" | absmsg.bash --sms



# *************************************************************************************************************************************************************
# * Глобальные переменные (в том числе для работы функций общего назначения)
# *************************************************************************************************************************************************************

# Ассоциативный массив __this содержит информацию об окружении текущего скрипта
declare -A __this

# Ассоциативный массив email содержит настройки для отправок электронных писем
declare -A email=(
	[from]=""
	[to]=""
	[smtp_address]=""
	[smtp_username]=""
	[smtp_password]=""
	[debug]="-q"
)

# Ассоциативный массив sms содержит настройки для отправок СМС сообщений
declare -A sms=(
	[username]=""
	[password]=""
	[url]=""
	[msisdn]=""
	[shortcode]=""
	[text]=""
	[POST]=""
	[GET]=""
	[debug]="2>/dev/null"
)

# Значения sms[POST] и sms[GET] вычисляются динамически вызовом eval
sms[POST]='--header Content-Type:\ application/json --data \{\ \"msisdn\":\""${sms[msisdn]}"\",\ \"shortcode\":\""${sms[shortcode]}"\",\ \"text\":\""${sms[text]}"\"\ \} --user ${sms[username]}:${sms[password]} ${sms[url]}'
sms[GET]='--user ${sms[username]}:${sms[password]} ${sms[url]}/'

# Ассоциативный массив log содержит настройки для записи сообщения в системный журнал
declare -A log=(
	[priority]="user.info"
)


# *************************************************************************************************************************************************************
# * Функции общего назначения (можно использовать, как библиотечные)
# *************************************************************************************************************************************************************

# -----------------------------------------------------------------------------
# Функция get_os
# возвращает название операционной системы текущего хоста
#
# Аргументы: нет
# Возвращаемое значение в stdout: название операционной системы текущего хоста
# -----------------------------------------------------------------------------
function get_os {
	local os=$(hostnamectl | grep 'Operating System: ' | awk '{print $3}')
	if [[ "$os" == "Ubuntu" ]]; then
		echo "ubuntu"
	elif [[ "$os" == "Fedora" ]]; then
		echo "fedora"
	else
		echo "$os"
	fi
	return 0
} # get_os



# *************************************************************************************************************************************************************
# * Функции, характерные только для задач текущего скрипта
# *************************************************************************************************************************************************************

# -----------------------------------------------------------------------------
# Функция init_variables
# инициализирует глобальные переменные скрипта, в том числе массив _this
#
# Аргументы: нет
# Возвращаемое значение: нет
# -----------------------------------------------------------------------------
function init_variables {

	# Инициализация элементов ассоциативного массива __this
	__this[hostname]=$(hostname)					# Имя хоста, на котором исполняется скрипт
	__this[path]=$(readlink -f $(dirname $0))		# Путь к текущему скрипту
	__this[filename]=$(basename $0)					# Имя файла текущего скрипта
	__this[os]="$(get_os)"							# Операционная система машины, на которой выполняется скрипт
	__this[username]=$(whoami)						# Имя системного пользователя, от лица которого происходит работа на выбранном хосте

	return 0
} # init_variables

# -----------------------------------------------------------------------------
# Функция main
# главная функция скрипта
#
# Аргументы: см. описание скрипта
# Возвращаемое значение:
# 0 - нет ошибок
# 100 - не установлен пакет, от которого зависит работа скрипта
# 101 - ошибка функции getopt при обработке аргументов функции main
# 102 - внутренняя ошибка при парсинге аргументов функции main, возможно требуется отладка
# 103 - ошибка: ~/.absmsg-credentials не доступен для чтения
# 104 - ошибка: ~/.absmsg-credentials содержит не полные данные
# 105 - ошибка при чтении файла из командной строки
# -----------------------------------------------------------------------------
function main {

	# 1. Инициализируем переменные скрипта
	# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	init_variables


	# 2. Проверка на наличие в системе пакетов sendemail и jq
	# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	if [[ -z "$(which sendemail 2>/dev/null)" ]]; then

		echo "Работа скрипта прервана, т.к. в системе не установлен пакет sendemail."
		[[ ${__this[os]} == "fedora" ]] && echo "sudo dnf install sendemail"
		[[ ${__this[os]} == "ubuntu" ]] && echo "sudo apt install sendemail"

		# 100 - не установлен пакет, от которого зависит работа скрипта
		return 100
	fi
	if [[ -z "$(which jq 2>/dev/null)" ]]; then

		echo "Работа скрипта прервана, т.к. в системе не установлен пакет jq."
		[[ ${__this[os]} == "fedora" ]] && echo "sudo dnf install jq"
		[[ ${__this[os]} == "ubuntu" ]] && echo "sudo apt install jq"

		# 100 - не установлен пакет, от которого зависит работа скрипта
		return 100
	fi


	# 3. Парсинг командной строки
	# ~~~~~~~~~~~~~~~~~~~~~~~~~~~
	local -A message=(
		[subject]=${__this[filename]}
		[credentials]=~/.absmsg-credentials
	)

	# В $temp помещаем обработанную строку с аргументами при вызове скрипта.
	# Известные аргументы (до аргумента "--" ) будут помещены в начало строки, остальные - после.
	local temp
	temp=$(getopt --options 'a:c:dehj:lp:s' --longoptions 'attach:,credentials:,debug,email,help,subject:,log,priority:,sms' --name "${__this[filename]}" -- "$@")
	if [ $? -ne 0 ]; then
		# 101 - ошибка функции getopt при обработке аргументов функции main
		echo "Ошибка функции getopt при обработке аргументов функции main"
		echo "Скрипт завершён с кодом 101"
		return 101
	fi

	# Замещаем аргументы функции main на новые из переменной $temp
	eval set -- "$temp"
	unset temp

	# В цикле обрабатываем известные аргументы
	while true; do
		case "$1" in
			'-a'|'--attach')
				email[attach]+="-a ${2} "
				shift 2
				continue
			;;
			'-c'|'--credentials')
				message[credentials]="$2"
				shift 2
				continue
			;;
			'-d'|'--debug')
				message[debug]=true
				shift
				continue
			;;
			'-e'|'--email')
				message[email]=true
				shift
				continue
			;;
			'-h'|'--help')
				message[help]=true
				shift
				break
			;;
			'-j'|'--subject')
				message[subject]="$2"
				shift 2
				continue
			;;
			'-l'|'--log')
				message[log]=true
				shift
				continue
			;;
			'-p'|'--priority')
				log[priority]="$2"
				shift 2
				continue
			;;
			'-s'|'--sms')
				message[sms]=true
				shift
				continue
			;;
			'--')
				# "--" - конец известных аргументов
				shift
				break
			;;
			*)
				# 102 - внутренняя ошибка при парсинге аргументов функции main, возможно требуется отладка
				echo "Внутренняя ошибка при парсинге аргументов функции main, возможно требуется отладка"
				echo "Скрипт завершён с кодом 102"
				return 102
			;;
		esac
	done


	# 4. Читаем .absmsg-credentials
	# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

	# Инициализация элементов ассоциативных массивов email и sms
	if [[ -r "${message[credentials]}" ]]; then
		. "${message[credentials]}"
		if [[	-z "${email[from]}"   || -z "${email[to]}"     || -z "${email[smtp_address]}" || -z "${email[smtp_username]}" || -z "${email[smtp_password]}" || \
				-z "${sms[username]}" || -z "${sms[password]}" || -z "${sms[url]}"            || -z "${sms[msisdn]}"          || -z "${sms[shortcode]}" ]]; then
			# 104 - ошибка: ${message[credentials]} содержит не полные данные
			echo "Ошибка: ${message[credentials]} содержит не полные данные"
			echo "Скрипт завершён с кодом 104"
			return 104
		fi
	else
		# 103 - ошибка: ${message[credentials]} не доступен для чтения
		echo "Ошибка: ${message[credentials]} не доступен для чтения"
		echo "Скрипт завершён с кодом 103"
		return 103
	fi


	# 5. Формируем текст сообщения
	# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	local -a message_strings
	local error_read_file

	if [[ "${message[help]}" != "true" ]]; then
		# Если дескриптор stdin открыт не в терминале (через pipe), см. 'man test' - читаем текст сообщения из pipe в массив строк
		[[ ! -t 0 ]] && mapfile message_strings
		# Все оставшиеся после разбора аргументы командной строки рассматриваем, как имена файлов с частями одного будущего сообщения
		while [[ $# -gt 0 ]] do
			[[ "$1" == "--" ]] && continue
			if [[ -s "$1" ]]; then
				# Последовательно добавляем каждый файл к сообщению
				mapfile -O "${#message_strings[@]}" message_strings < "$1"
				shift
			else
				# Если хоть один файл не существует или имеет нулевую длину, то будет выход по ошибке с показом подсказки.
				message[help]=true
				error_read_file="$1"
				break
			fi
		done
	fi
	# Если пользователь вообще не задал текст сообщения, то высылаем временную метку
	[[ ${#message_strings[@]} -eq 0 ]] && message_strings=( "$(whoami) on $(hostname) at $(date)" )


	# 6. Основная часть
	# ~~~~~~~~~~~~~~~~~

	# Если была запрошена помощь (или была ошибка при чтении файлов шагом ранее)
	if [[ "${message[help]}" == "true" ]]; then
		echo "${__this[filename]}   version 0.1, © 2024 by Sergey Vasiliev aka abs."
		echo "${__this[filename]} - скрипт для упрощенной одновременной отправки сообщений по электронной почте, СМС и в системный журнал. Текст сообщения берётся из стандартного потока stdin и содержимого файлов - аргументов командной строки. Все не разобранные опции считаются именами файлов, которые последовательно добавляются к итоговому сообщению. Если сообщение вообще не задано, то в сообщение записывается имя текущего пользователя, имя хоста, время и дата."
		echo ""
		echo "${__this[filename]} comes with ABSOLUTELY NO WARRANTY. This is free software, and you are welcome to redistribute it under certain conditions.  See  the GNU General Public Licence for details."
		echo ""
		echo "Использование: ${__this[filename]} [ОПЦИЯ] [--] [FILE1] [FILE2] ..."
		echo ""
		echo "Опции:"
		echo "-e, --email                        отправить сообщение по электронной почте"
		echo "-j, --subject \"Тема письма\"        тема письма; по-умолчанию используется имя скрипта '${__this[filename]}'; опция игнорируется при выборе способа отправки сообщений sms"
		echo "-a, --attach \"Имя файла\"           вложение к письму: имя файла с путём; опция может быть использована многократно; опция игнорируется при выборе других способов отправки сообщений"
		echo ""
		echo "-l, --log                          сделать запись в системном журнале"
		echo "-j, --subject \"Тег\"                тег записи в системном журнале; пробелы принудительно меняются на знаки подчёркивания '_'; если тег не задан, то используется имя скрипта '${__this[filename]}'; опция игнорируется при выборе способа отправки сообщений sms"
		echo "-p, --priority \"facility.level\"    описание возможных комбинаций имён facility и level смотрите 'man logger'; по-умолчанию используется user.info; опция игнорируется при выборе других способов отправки сообщений"
		echo ""
		echo "-s, --sms                          отправить СМС"
		echo ""
		echo "-c, --credentials \"Имя файла\"      путь к файлу с приватными данными для отправки сообщений по электронной почте и СМС; по умолчанию - ~/.absmsg-credentials"
		echo "-d, --debug                        режим отладки для вывода диагностических сообщений используемых команд"
		echo "-h, --help                         показывает эту подсказку"
		echo ""
		echo "Примеры использования:"
		echo "echo \"Сообщение\" | ${__this[filename]} --log --email"
		echo "cat /etc/passwd | ${__this[filename]} --email --subject \"Файл passwd\""
		echo "${__this[filename]} --email --subject \"Файл passwd\" </etc/passwd"
		echo "echo \"Сообщение\" | ${__this[filename]} --log --email --subject \"Письмо с вложениями\" --attach \"/etc/passwd\" --attach /etc/group -d"
		echo "echo \"Сообщение\" | ${__this[filename]} --log --subject \"Какой-то заголовок\" --priority cron.err"
		echo "echo \"Сообщение\" | ${__this[filename]} -e -j \"Какой-то заголовок\" -d ~/.nanorc ~/.bashrc"
		echo "${__this[filename]} -e -j \"Какой-то заголовок\" -- ~/.nanorc ~/.bashrc"
		echo "${__this[filename]} -el"
		echo "echo \"Сообщение\" | ${__this[filename]} --sms"


		# Была ошибка при чтении файла из аргументов в командной строке
		if [[ -n "$error_read_file" ]]; then
			# 105 - ошибка при чтении файла из командной строки
			echo ""
			echo ""
			echo "Ошибка при чтении файла ${error_read_file}"
			echo "Файл не существует или имеет нулевую длину"
			echo "Скрипт завершён с кодом 105"
			return 105
		fi

		return 0;
	fi

	# Включаем режим отладки по запросу пользователя
	[[ "${message[debug]}" == "true" ]] && email[debug]="-v" && sms[debug]="--verbose" && set -x

	# Отправляем сообщение по электронной почте
	[[ "${message[email]}" == "true" ]] && eval sendemail -f "${email[from]}" -t "${email[to]}" -o message-charset=utf-8 -s "${email[smtp_address]}" -xu "${email[smtp_username]}" -xp "${email[smtp_password]}" "${email[debug]}" -u \'"${message[subject]}"\' -m \'"${message_strings[@]}"\' ${email[attach]}
	# ... в системный журнал
	[[ "${message[log]}"   == "true" ]] && printf "%s" "${message_strings[@]}" | logger -t "${message[subject]// /_}" --priority "${log[priority]}" --
	# ... по СМС
	if [[ "${message[sms]}" == "true" ]]; then
		# Отправка СМС
		sms[text]="${message_strings[*]//$'\n'/ }"
		local result1=$(eval curl "${sms[POST]} ${sms[debug]}")
		local result2=""
		# Если был запрошен режим отладки,то дополнительно делаем запрос о состоянии отправленного сообщения
		if [[ "${message[debug]}" == "true" ]]; then
			local message_id=$(echo "$result1" | jq --raw-output ".result.uid")
			result2=$(eval curl "${sms[GET]}${message_id} ${sms[debug]}")
			set +x
		fi
		# Фиксируем факт отправки и все результаты в системном журнале
		logger -t "${__this[filename]}" --priority "user.info" -- --------------------
		logger -t "${__this[filename]}" --priority "user.info" -- SMS send to Tele2 by "$(whoami) on $(hostname) at $(date)"
		logger -t "${__this[filename]}" --priority "user.info" -- Command: $(eval echo "curl ${sms[POST]} ${sms[debug]}")
		logger -t "${__this[filename]}" --priority "user.info" -- Result : "$result1"
		if [[ "${sms[debug]}" == "--verbose" ]]; then
			logger -t "${__this[filename]}" --priority "user.info" -- Command: $(eval echo "curl ${sms[GET]}${message_id} ${sms[debug]}")
			logger -t "${__this[filename]}" --priority "user.info" -- Result : "$result2"
		fi
	fi

	# Выключаем установленный режим отладки
	[[ "${message[debug]}" == "true" ]] && set +x

	return 0;
} # main



# *************************************************************************************************************************************************************
# * Сам скрипт 😊
# *************************************************************************************************************************************************************

main "$@"
exit $?

# *************************************************************************************************************************************************************
