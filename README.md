# Описание

**absipcam.bash** - скрипт для контроля ежедневного количества и объёма видеофайлов, поступающих от камер видеонаблюдения. При отклонениях в количестве или объёме генерируются тревожные сообщения (посредством absmsg.bash). Вся информация дублируется в системном журнале.<br/>

**absmsg.bash** - скрипт для упрощенной одновременной отправки сообщений по электронной почте, СМС и в системный журнал. Текст сообщения берётся из стандартного потока stdin и содержимого файлов - аргументов командной строки. Все не разобранные опции считаются именами файлов, которые последовательно добавляются к итоговому сообщению. Если сообщение вообще не задано, то в сообщение записывается имя текущего пользователя, имя хоста, время и дата.<br/>


# Установка

1. **sources/*.bash** разместить в одном из каталогов переменной $PATH<br/>
0. **sources/*-completion** - файлы автоматических дополнений соответствующих скриптов bash - разместить в /etc/bash_completion.d/ (работает в Fedora 40)<br/>
0. Взяв за основу **sources/.absmsg-credentials.EXAMPLE**, нужно создать свой файл с приватными данными для скрипта absmsg.bash. Данные используются для отправки сообщений по электронной почте и СМС. Без аргумента --credentials скрипт absmsg.bash обращается к файлу ~/.absmsg-credentials Нужно учитывать это при запуске скриптов от sudo: или разместить этот файл в домашнем каталоге root, или указать во всех скриптах, которые используют absmsg.bash, другое расположение этого файла.
# Использование

## sources/absipcam.bash
```
Использование: absipcam.bash [ОПЦИЯ] ...

Опции:
-a, --only-alarm                 выводить информацию только в случае проблем с количеством или объёмом видеофайлов
-e, --email                      отправить уведомление по электронной почте
-s, --sms                        при наличии тревожных сообщений отправить уведомление по СМС
-q, --quiet                      не выводить информацию на экран
-c, --credentials "Имя файла"    путь к файлу с приватными данными для скрипта absmsg.bash; по умолчанию - ~/.absmsg-credentials
-h, --help                       показывает эту подсказку
```

## sources/absmsg.bash
```
Использование: absmsg.bash [ОПЦИЯ] [--] [FILE1] [FILE2] ...

Опции:
-e, --email                        отправить сообщение по электронной почте
-j, --subject "Тема письма"        тема письма; по-умолчанию используется имя скрипта 'absmsg.bash'; опция игнорируется при выборе способа отправки сообщений sms
-a, --attach "Имя файла"           вложение к письму: имя файла с путём; опция может быть использована многократно; опция игнорируется при выборе других способов отправки сообщений

-l, --log                          сделать запись в системном журнале
-j, --subject "Тег"                тег записи в системном журнале; пробелы принудительно меняются на знаки подчёркивания '_'; если тег не задан, то используется имя скрипта 'absmsg.bash'; опция игнорируется при выборе способа отправки сообщений sms
-p, --priority "facility.level"    описание возможных комбинаций имён facility и level смотрите 'man logger'; по-умолчанию используется user.info; опция игнорируется при выборе других способов отправки сообщений

-s, --sms                          отправить СМС

-c, --credentials "Имя файла"      путь к файлу с приватными данными для отправки сообщений по электронной почте и СМС; по умолчанию - ~/.absmsg-credentials
-d, --debug                        режим отладки для вывода диагностических сообщений используемых команд
-h, --help                         показывает эту подсказку

Примеры использования:
echo "Сообщение" | absmsg.bash --log --email
cat /etc/passwd | absmsg.bash --email --subject "Файл passwd"
absmsg.bash --email --subject "Файл passwd" </etc/passwd
echo "Сообщение" | absmsg.bash --log --email --subject "Письмо с вложениями" --attach "/etc/passwd" --attach /etc/group -d
echo "Сообщение" | absmsg.bash --log --subject "Какой-то заголовок" --priority cron.err
echo "Сообщение" | absmsg.bash -e -j "Какой-то заголовок" -d ~/.nanorc ~/.bashrc
absmsg.bash -e -j "Какой-то заголовок" -- ~/.nanorc ~/.bashrc
absmsg.bash -el
echo "Сообщение" | absmsg.bash --sms
```


<br/>
<br/>
<br/>

---
© 2024 Sergey Vasiliev<br/>
- <a href="mailto:vasiliev.s@komdiv.org" target="_blank">vasiliev.s@komdiv.org</a><br/>
- <a href="mailto:abs.tambov@gmail.com" target="_blank">abs.tambov@gmail.com</a><br/>
