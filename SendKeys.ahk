#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
#NoTrayIcon
#SingleInstance Off
SetBatchLines -1
SetTitleMatchMode, slow

targetWindow = ahk_pid %1%
delay = %2%
for n, param in A_Args {
    IfGreater, n, 2
    {
        WinActivate, %targetWindow%
        WinWaitActive, %targetWindow%
        Send,%param%
        sleep, %delay%
    }
}