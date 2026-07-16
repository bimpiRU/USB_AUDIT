@echo off
chcp 65001 >nul
cd /d "%~dp0"

:: [UAC_CHECK] Проверка и запрос привилегий Администратора.
:: Необходима для выполнения низкоуровневых сетевых операций Nmap в Windows 11 (подмена MAC, фрагментация).
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :RunAudit
) else (
    goto :GetAdmin
)

:GetAdmin
echo [+] Запрос прав администратора для скрытного гибридного аудита...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd -ArgumentList '/c \'%~dp0%~nx0\' ActualRun' -Verb RunAs"
exit /b

:RunAudit
if "%~1"=="ActualRun" (
    cd /d "%~dp0"
)

echo ======================================================================
echo   WSL 1 HYBRID AUDIT ENGINE v7.5 (Core: Self-Documenting Standard)
echo ======================================================================
echo [*] Фиксация рабочей директории Windows: %cd%

:: [DEPENDENCY_CHECK] Проверка наличия обязательного Linux-компонента
if not exist "linux_audit.sh" (
    echo [-] КРИТИЧЕСКАЯ ОШИБКА: Компонент linux_audit.sh не обнаружен в папке %cd%
    pause
    exit /b 1
)

if not exist "LINUX_AUDIT_REPORTS" mkdir LINUX_AUDIT_REPORTS

:: [WSL_PURGE] Сброс фонового кэша и остановка всех активных контейнеров WSL.
:: Гарантирует очистку оперативной памяти от зависших старых версий скриптов перед стартом.
echo [*] Сброс фоновых процессов и кэша подсистемы WSL...
wsl --shutdown

echo [*] Инициализация сетевых интерфейсов...
echo ----------------------------------------------------------------------

:: [NETWORK_DETECTION] Сценарий PowerShell для автоматического поиска активного физического адаптера.
:: Фильтрует локальную петлю (127.0.0.1) и авто-IP (169.254.x.x), ищет реальные сети 192.168.x.x или 172.x.x.x.
:: Превращает IP-адрес хоста в маску подсети класса С (/24) для последующего сканирования.
for /f "delims=" %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -match '^(192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' } | Select-Object -First 1).IPAddress; if ($ip) { ($ip.Split('.')[0..2] -join '.') + '.0/24' } else { 'NONE' }"') do set "SUBNET_SCAN=%%A"

if "%SUBNET_SCAN%"=="NONE" (
    echo [-] ОШИБКА: Активное физическое сетевое подключение хоста не обнаружено.
    pause
    exit /b 1
)

echo [+] Обнаружен физический диапазон сети: %SUBNET_SCAN%
echo [*] Запуск нативного Nmap сканирования в режиме максимальной маскировки...
echo [*] Пожалуйста, подождите. Идет асинхронный сбор данных...
echo ----------------------------------------------------------------------

:: Форматирование уникальных путей отчетов на основе текущей метки времени сессии
for /f %%A in ('powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"') do set "TIMESTAMP=%%A"
set "REPORT_FILE=LINUX_AUDIT_REPORTS\Audit_Output_%TIMESTAMP%.txt"
set "TEMP_NMAP=LINUX_AUDIT_REPORTS\win_nmap_temp.txt"

:: [STEALTH_NETWORK_SCAN] Нативный запуск сканера Windows через Winsock API хоста.
:: Обходит любые ограничения сетевой изоляции WSL (такие как пустой интерфейс dev).
:: -f : Разделение пакетов на фрагменты (обход систем обнаружения вторжений IDS/IPS).
:: --randomize-hosts : Хаотичный (непоследовательный) опрос IP-адресов в подсети для маскировки паттерна.
:: --spoof-mac 0 : Генерация случайного MAC-адреса для маскировки сетевой карты под другого вендора.
:: --scan-delay 300ms : Искусственная задержка между пакетами для снижения сетевого шума.
:: --open : Игнорировать закрытые порты, собирать информацию только об активных службах.
"C:\Program Files (x86)\Nmap\nmap.exe" -sT -p 21,22,23,80,443,445,3389,8080 -T3 --open -f --randomize-hosts --spoof-mac 0 --scan-delay 300ms %SUBNET_SCAN% > "%TEMP_NMAP%"

echo [+] Сканирование скрытным методом успешно завершено.
echo [*] Перенос данных, запуск анализа и сохранение отчета на флешку...
echo ----------------------------------------------------------------------

:: [WSL_PRIVILEGE_CONFIGURATION] Перевод пользователя kali в беспарольный режим выполнения sudo.
:: Необходим для корректного выполнения низкоуровневых Linux-команд (например, работы с сокетами Python).
wsl -u root bash -c "echo 'kali ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/kali"

:: [DATA_STREAM_PIPELINE] Многостадийный перенос данных в память подсистемы Linux.
:: 1. type "linux_audit.sh" | wsl ... : Заталкивает исходный код bash-анализатора напрямую в виртуальную папку /tmp/audit.sh,
::    полностью исключая ошибки несмонтированных дисков Windows (wsl: Failed to translate).
:: 2. type "%TEMP_NMAP%" | wsl ... : Скармливает собранный лог портов Windows на вход созданному скрипту через стандартный ввод (stdin).
:: 3. > "%REPORT_FILE%" 2>&1 : Перехватывает весь консольный текстовый вывод Linux и записывает его в финальный UTF-8 файл на флешку.
type "linux_audit.sh" | wsl bash -c "tr -d '\r' > /tmp/audit.sh && chmod +x /tmp/audit.sh"
type "%TEMP_NMAP%" | wsl bash -c "/tmp/audit.sh" > "%REPORT_FILE%" 2>&1

:: [VERIFICATION_STAGE] Проверка физического создания и заполнения файла отчета
if exist "%REPORT_FILE%" (
    type "%REPORT_FILE%"
) else (
    echo [-] КРИТИЧЕСКАЯ ОШИБКА: Файл отчета не был создан на флешке!
)

:: [CLEANUP] Удаление временных промежуточных логов для обеспечения скрытности следов на флешке
if exist "%TEMP_NMAP%" del /f /q "%TEMP_NMAP%"

echo.
echo ======================================================================
echo [+] ГИБРИДНЫЙ АУДИТ И АКТИВНАЯ ВАЛИДАЦИЯ УСПЕШНО ЗАВЕРШЕНЫ.
echo [+] Данные сохранены: %REPORT_FILE%
echo ======================================================================
echo.
pause
