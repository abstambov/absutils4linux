#!/bin/bash

# absipcam.bash   version 0.1, © 2024 by Sergey Vasiliev aka abs.
# absipcam.bash - скрипт для контроля ежедневного количества и объёма видеофайлов, поступающих от камер видеонаблюдения. При отклонениях в количестве или объёме генерируются тревожные сообщения (посредством absmsg.bash). Вся информация дублируется в системном журнале.
# 
# absipcam.bash comes with ABSOLUTELY NO WARRANTY. This is free software, and you are welcome to redistribute it under certain conditions.  See  the GNU General Public Licence for details.
# 
# Использование: absipcam.bash [ОПЦИЯ] ...
# 
# Опции:
# -a, --only-alarm    выводить информацию только в случае проблем с количеством или объёмом видеофайлов
# -e, --email         отправить уведомление по электронной почте
# -s, --sms           при наличии тревожных сообщений отправить уведомление по СМС
# -q, --quiet         не выводить информацию на экран
# -h, --help          показывает эту подсказку



# *************************************************************************************************************************************************************
# * Глобальные переменные (в том числе для работы функций общего назначения)
# *************************************************************************************************************************************************************

# Ассоциативный массив __this содержит информацию об окружении текущего скрипта
declare -A __this

# Путь к каталогу, который содержит подкаталоги с именами камер
declare -r path_to_videos="/home/vasiliev-s/.камеры/video"

# Название камер
declare -a -r ipcam_names=( IPBUH1Y IPBUH2V IPRSC_CH1Y IPRSC_CH2V IPRSC_TE1Y IPRSC_TE2V IPSK1Y IPSK2V )

# Настройки тревоги
declare -i -r min_total_size=1900		# Минимальный суммарный размер видеофайлов (в MiB) за текущий день по одной камере
declare -i -r min_total_count=96		# Минимальное число видеофайлов за текущий день по одной камере (4 видео в час)
declare -i -r max_delta_of_size=-20		# Максимально допустимое отклонение в меньшую сторону от среднего в процентах за неделю для суммарного размера    видеофайлов
declare -i -r max_delta_of_count=-20	# Максимально допустимое отклонение в меньшую сторону от среднего в процентах за неделю для суммарного количества видеофайлов

# Путь к absmsg.bash
declare -r path_to_absmsg="/home/share/install/scripts/absmsg.bash"



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

# -----------------------------------------------------------------------------
# Функция spinner
# бесконечно выводит вращающуюся палку на экран
#
# Аргументы: нет
# Возвращаемое: нет
# -----------------------------------------------------------------------------
function spinner {
	local i=1
	local -r symbols="/-\|"
	echo -n ' '
	while [[ true ]]; do
		printf "\b${symbols:i++%${#symbols}:1}"
		sleep .1
	done
} # spinner



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
# 101 - скрипт absmsg.bash не доступен для вызова
# 102 - ошибка функции getopt при обработке аргументов функции main
# 103 - внутренняя ошибка при парсинге аргументов функции main, возможно требуется отладка
# 104 - ошибка в аргументах командной строки
# 105 - были тревожные сообщения от камер
# -----------------------------------------------------------------------------
function main {

	# 1. Инициализируем переменные скрипта
	# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	init_variables

	# 2. Проверка на наличие в системе пакетов sendemail, jq (требуются для работы absmsg.bash) и absmsg.bash
	# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
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

	if [[ ! -x "${__this[path]}/absmsg.bash" ]]; then
		# 101 - скрипт absmsg.bash не доступен для вызова
		echo "Ошибка cкрипт absmsg.bash не доступен для вызова"
		echo "Скрипт завершён с кодом 101"
		return 101
	fi


	# 3. Парсинг командной строки
	# ~~~~~~~~~~~~~~~~~~~~~~~~~~~
	local -A opt

	# В $temp помещаем обработанную строку с аргументами при вызове скрипта.
	# Известные аргументы (до аргумента "--" ) будут помещены в начало строки, остальные - после.
	local temp
	temp=$(getopt --options 'aehsq' --longoptions 'only-alarm,email,help,sms,quiet' --name "${__this[filename]}" -- "$@")
	if [[ $? -ne 0 ]]; then
		# 102 - ошибка функции getopt при обработке аргументов функции main
		echo "Ошибка функции getopt при обработке аргументов функции main"
		echo "Скрипт завершён с кодом 102"
		return 102
	fi

	# Замещаем аргументы функции main на новые из переменной $temp
	eval set -- "$temp"
	unset temp

	# В цикле обрабатываем известные аргументы
	while true; do
		case "$1" in
			'-a'|'--only-alarm')
				opt[only_alarm]=true
				shift
				continue
			;;
			'-e'|'--email')
				opt[email]=true
				shift
				continue
			;;
			'-h'|'--help')
				opt[help]=true
				shift
				continue
			;;
			'-s'|'--sms')
				opt[sms]=true
				shift
				continue
			;;
			'-q'|'--quiet')
				opt[quiet]=true
				shift
				continue
			;;
			'--')
				# "--" - конец известных аргументов
				shift
				break
			;;
			*)
				# 103 - внутренняя ошибка при парсинге аргументов функции main, возможно требуется отладка
				echo "Внутренняя ошибка при парсинге аргументов функции main, возможно требуется отладка"
				echo "Скрипт завершён с кодом 103"
				return 103
			;;
		esac
	done

	# Если была запрошена помощь (или остались нераспознаные аргументы командной строки)
	if [[ -n "${opt[help]}" || $# -ne 0 ]]; then
		echo "${__this[filename]}   version 0.1, © 2024 by Sergey Vasiliev aka abs."
		echo "${__this[filename]} - скрипт для контроля ежедневного количества и объёма видеофайлов, поступающих от камер видеонаблюдения. При отклонениях в количестве или объёме генерируются тревожные сообщения (посредством absmsg.bash). Вся информация дублируется в системном журнале."
		echo ""
		echo "${__this[filename]} comes with ABSOLUTELY NO WARRANTY. This is free software, and you are welcome to redistribute it under certain conditions.  See  the GNU General Public Licence for details."
		echo ""
		echo "Использование: ${__this[filename]} [ОПЦИЯ] ..."
		echo ""
		echo "Опции:"
		echo "-a, --only-alarm    выводить информацию только в случае проблем с количеством или объёмом видеофайлов"
		echo "-e, --email         отправить уведомление по электронной почте"
		echo "-s, --sms           при наличии тревожных сообщений отправить уведомление по СМС"
		echo "-q, --quiet         не выводить информацию на экран"
		echo "-h, --help          показывает эту подсказку"

		# Была ошибка в аргументах командной строки
		if [[ $# -ne 0 ]]; then
			echo ""
			echo ""
			echo "Ошибка в аргументах командной строки: ${@}"
			echo "Скрипт завершён с кодом 104"

			# 104 - ошибка в аргументах командной строки
			return 104
		fi

		return 0
	fi


	# 4. Основная часть
	# ~~~~~~~~~~~~~~~~~

	# Запускаем спиннер
	if [[ -z "${opt[quiet]}" ]]; then
		local spinner_pid
		spinner &
		spinner_pid=$!
	fi

	# Переменные
	local -A size_of_videos				# Содержит общий размер видеофайлов по дням
	local -A count_of_videos			# Содержит общее количество видеофайлов по дням
	local -A delta_of_size				# Содержит отклонения в общем размере видеофайлов по дням
	local -A delta_of_count				# Содержит отклонения в общем количестве видеофайлов по дням
	local -a alarm_yesterday			# Содержит тревожные сообщения за вчера
	local -a alarm_today				# Содержит тревожные сообщения за сегодня
	local -A alarm=( [type]="info" )	# Вспомогательный массив для обработки тревожных сообщений
	local -a message					# Содержит сформированный текст для экрана и/или электронной почты
	local ipcam
	local i

	# -----------------------------------------------------------------------------
	# Функция ipcam_check_values
	# проверяет значения в ассоциативных массивах size_of_videos, сount_of_videos,
	# delta_of_size и delta_of_count по передаваемому индексу $2 на допустимые
	# Аргументы:
	# $1 - массив, к которому добавятся строки тревожных сообщений
	# $2 - индекс проверяемого элемента
	# Возвращаемое значение:
	# массив "$1" содержит строки с тревожными сообщениями
	# -----------------------------------------------------------------------------
	function ipcam_check_values {
		local -n arr="$1"
		local delta1
		local delta2

		printf -v delta1 "%.0f" ${delta_of_size["$2"]}
		printf -v delta2 "%.0f" ${delta_of_count["$2"]}

		[[ ${size_of_videos["$2"]}  -lt $min_total_size  ]] && printf -v 'arr["${#arr[@]}"]' "cуммарный размер видеофайлов (%u МиБ) меньше допустимо минимального (%u МиБ)" ${size_of_videos["$2"]} $min_total_size
		[[ ${count_of_videos["$2"]} -lt $min_total_count ]] && printf -v 'arr["${#arr[@]}"]' "число видеофайлов (%u) меньше допустимо минимального (%u)" ${count_of_videos["$2"]} $min_total_count
		[[ $delta1 -lt $max_delta_of_size  ]] && printf -v 'arr["${#arr[@]}"]' "отклонение в меньшую сторону от среднего суммарного размера видеофайлов (%+06.2f%%), что ниже предельно допустимого (%s%%)"    ${delta_of_size["$2"]}  $max_delta_of_size
		#[[ $delta2 -lt $max_delta_of_count ]] && printf -v 'arr["${#arr[@]}"]' "отклонение в меньшую сторону от среднего суммарного количества видеофайлов (%+06.2f%%), что ниже предельно допустимого (%s%%)" ${delta_of_count["$2"]} $max_delta_of_count

		return 0
	} # ipcam_check_values

	# -----------------------------------------------------------------------------
	# Функция ipcam_echo_info
	# вывод информации о текущей камере в stdout в соответствии со значениями
	# переменных скрипта и опций командной строки
	# Аргументы: нет
	# Возвращаемое значение:
	# в stdout выводится информация о текущей камере
	# -----------------------------------------------------------------------------
	function ipcam_echo_info {

		if [[ -z "${opt[only_alarm]}" || -n "${alarm[status]}" ]]; then
			echo "Камера ${ipcam}${alarm[status]}"
		fi
		if [[ -z "${opt[only_alarm]}" ]]; then
			printf " в среднем за неделю в день . %3u видео на %3u МиБ\n"                                     ${count_of_videos[average]}       ${size_of_videos[average]}
			printf " вчера ...................... %3u видео на %3u МиБ (%+06.2f%% и %+06.2f%% от среднего)\n" ${count_of_videos[yesterday]}     ${size_of_videos[yesterday]}     ${delta_of_count[yesterday]}     ${delta_of_size[yesterday]}
			printf " cегодня .................... %3u видео на %3u МиБ\n"                                     ${count_of_videos[today]}         ${size_of_videos[today]}
			printf " ~ будет к концу дня ........ %3u видео на %3u МиБ (%+06.2f%% и %+06.2f%% от среднего)\n" ${count_of_videos[extrapolation]} ${size_of_videos[extrapolation]} ${delta_of_count[extrapolation]} ${delta_of_size[extrapolation]}
			echo ""
		fi
		if [[ ${#alarm_today[@]} -gt 0 ]]; then
			if [[ ${#alarm_yesterday[@]} -gt 0 ]]; then
				echo " тревожные сообщения вчера:"
				for i in "${alarm_yesterday[@]}"; do
					echo "  - ${i}"
				done
			fi
			echo " тревожные сообщения сегодня (на конец дня):"
			for i in "${alarm_today[@]}"; do
				echo "  - ${i}"
			done
			echo ""
		fi

		return 0
	} # ipcam_echo_info
	# -----------------------------------------------------------------------------

	for ipcam in "${ipcam_names[@]}"; do

		# Обнуляем массивы тревожных сообщений
		alarm_yesterday=()
		alarm_today=()
		alarm[status]=""

		# Получаем контрольные значения за 7 дней, за вчерашний день и за сегодня: общий размер видеофайлов и их число
		size_of_videos=(
			[average]=$(( $(find "${path_to_videos}/${ipcam}" -maxdepth 1 -type f -daystart -mtime -9 -mtime +1 | xargs ls --size --block-size=1 | awk '{print $1}' | paste -s -d '+' | bc) / 7 ))
			[yesterday]=$(  find "${path_to_videos}/${ipcam}" -maxdepth 1 -type f -daystart -mtime -2 -mtime +0 | xargs ls --size --block-size=1 | awk '{print $1}' | paste -s -d '+' | bc)
			[today]=$(      find "${path_to_videos}/${ipcam}" -maxdepth 1 -type f -daystart -mtime 0            | xargs ls --size --block-size=1 | awk '{print $1}' | paste -s -d '+' | bc)
			[extrapolation]=""
		)
		count_of_videos=(
			[average]=$(( $(find "${path_to_videos}/${ipcam}" -maxdepth 1 -type f -daystart -mtime -9 -mtime +1 | wc -l) / 7 ))
			[yesterday]=$(  find "${path_to_videos}/${ipcam}" -maxdepth 1 -type f -daystart -mtime -2 -mtime +0 | wc -l)
			[today]=$(      find "${path_to_videos}/${ipcam}" -maxdepth 1 -type f -daystart -mtime 0 | wc -l)
			[extrapolation]=""
		)
		delta_of_size=(
			[yesterday]=$( bc <<< "scale=2; ${size_of_videos[yesterday]} * 100 / ${size_of_videos[average]} - 100" )
			[extrapolation]=""
		)
		delta_of_count=(
			[yesterday]=$(( count_of_videos[yesterday] * 100 / count_of_videos[average] - 100 ))
			[extrapolation]=""
		)

		# Перевод из байтов в мегабайты
		(( size_of_videos[average] /= 1024*1024 ))
		(( size_of_videos[yesterday] /= 1024*1024 ))
		(( size_of_videos[today] /= 1024*1024 ))

		# Экстраполируем значения сегодняшнего дня, применяем коэффициент [число_секунд_в_сутках]/[число_секунд_с_начала_суток]
		i=$( bc <<< "scale=2; 86400 / ( $(date +%s) - $(date -d 'today 00:00:00' +%s) )")

		size_of_videos[extrapolation]=$(  bc <<< "scale=2; ${size_of_videos[today]}  * ${i}" )
		count_of_videos[extrapolation]=$( bc <<< "scale=2; ${count_of_videos[today]} * ${i}" )

		size_of_videos[extrapolation]="${size_of_videos[extrapolation]%.*}"
		count_of_videos[extrapolation]="${count_of_videos[extrapolation]%.*}"

		delta_of_size[extrapolation]=$( bc <<< "scale=2; ${size_of_videos[extrapolation]} * 100 / ${size_of_videos[average]} - 100" )
		delta_of_count[extrapolation]=$( bc <<< "scale=2; ${count_of_videos[extrapolation]} * 100 / ${count_of_videos[average]} - 100" )

		# У переменных, которые содержат число с плавающей точкой, меняем разделитель на запятую
		delta_of_count[yesterday]=${delta_of_count[yesterday]//./,}
		delta_of_size[yesterday]=${delta_of_size[yesterday]//./,}
		delta_of_count[extrapolation]=${delta_of_count[extrapolation]//./,}
		delta_of_size[extrapolation]=${delta_of_size[extrapolation]//./,}

		# Проверка значений вчерашнего и сегодняшнего дня
		ipcam_check_values "alarm_yesterday" "yesterday"
		ipcam_check_values "alarm_today" "extrapolation"

		# В зависимости от того, были ли тревожные сообщения только в текущем дне, или были ещё и вчера, формируем массив alarm
		if [[ ${#alarm_today[@]} -gt 0 ]]; then
			[[ -n ${alarm[ipcams]} ]] && alarm[ipcams]+=", "
			alarm[ipcams]+="$ipcam"

			if [[ ${#alarm_yesterday[@]} -gt 0 ]]; then
				# Проблема с камерой была вчера и наблюдается сегодня
				alarm[type]="error"
				alarm[status]=": ТРЕБУЕТ ВНИМАНИЯ! ПРОБЛЕМЫ С ЗАПИСЬЮ ВИДЕО ОТ КАМЕРЫ!"
				alarm[ipcams]+=" (не работает)"
			else
				# Проблема с камерой наблюдается только сегодня, вчера всё было хорошо
				[[ "${alarm[type]}" != "error" ]] && alarm[type]="warning"
				alarm[status]=": сегодня ($(date +'%F')) проблемы с видеопотоком"
			fi
		fi

		# Перенаправим вывод о камере в массив для дальнейших манипуляций
		mapfile -t -O ${#message[@]} message < <(ipcam_echo_info)
	done

	# Формируем alarm[ipcams] - это тема сообщений по email и/или содержание СМС уведомления
	if [[ -z ${alarm[ipcams]} ]]; then
		# Если нет тревог
		alarm[ipcams]="Похоже, что все камеры работают нормально."
		[[ -n "${opt[only_alarm]}" ]] && message=( "${alarm[ipcams]}" "" )
		alarm[ipcams]="КАМЕРЫ $(date +'%F') | ${alarm[ipcams]}"
	else
		# Были тревожные сообщения
		alarm[ipcams]="КАМЕРЫ $(date +'%F') | Проблемы: ${alarm[ipcams]}."
		[[ "${alarm[type]}" == "warning" ]] && alarm[ipcams]="⚠ ${alarm[ipcams]}"
		[[ "${alarm[type]}" == "error"   ]] && alarm[ipcams]="❗ ${alarm[ipcams]}"
	fi

	# Останавливаем спиннер
	if [[ -z "${opt[quiet]}" ]]; then
		kill $spinner_pid
		wait $spinner_pid 2>/dev/null
		printf "\b"
	fi

	# Вывод на экран, сообщения на электронную почту и СМС, запись в системный журнал
	[[ -z "${opt[quiet]}" ]] && printf "%s\n" "${message[@]}"
	[[ -n "${opt[email]}" && ( "${alarm[type]}" != "info" || -z "${opt[only_alarm]}" ) ]] && printf "%s\n" "${message[@]}" | "${__this[path]}/absmsg.bash" --email --subject "${alarm[ipcams]}"
	[[ -n "${opt[sms]}"   &&   "${alarm[type]}" != "info" ]]                              && echo "${alarm[ipcams]}" | "${__this[path]}/absmsg.bash" --sms

	# Фиксируем информацию о камерах в системный журнал
	printf "%s\n%s\n" "--------------------" "${message[@]}" | logger -t ""${__this[filename]}"" --priority "user.${alarm[type]}" --

	# 105 - были тревожные сообщения от камер
	[[ "${alarm[type]}" != "info" ]] && return 105

	return 0
} # main



# *************************************************************************************************************************************************************
# * Сам скрипт 😊
# *************************************************************************************************************************************************************

main "$@"
exit $?

# *************************************************************************************************************************************************************
