#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

#Include XInput.ahk
#Include AHK-ViGEm-Bus-v2.ahk

; Alta precisión de temporizador (1 ms)
DllCall("Winmm\timeBeginPeriod", "UInt", 1)

; ── Configuración ───────────────────────────────────────
global FAST_INTERVAL := 45      ; tiempo entre inicios de pulsos rápidos
global SLOW_INTERVAL := 300     ; tiempo entre inicios de pulsos lentos (A/Y)
global PULSE_HOLD_MS := 18      ; duración real que el botón/gatillo está presionado

XInput_Init()
global controller := ViGEmXb360()

global BUTTONS := Map(
    "A",  XINPUT_GAMEPAD_A,
    "B",  XINPUT_GAMEPAD_B,
    "X",  XINPUT_GAMEPAD_X,
    "Y",  XINPUT_GAMEPAD_Y,
    "LB", XINPUT_GAMEPAD_LEFT_SHOULDER,
    "RB", XINPUT_GAMEPAD_RIGHT_SHOULDER
)

global pressed       := Map()
global pulseActive   := Map()
global nextPulseTime := Map()
global offTime       := Map()

for k in ["A","B","X","Y","LB","RB","LT","RT"] {
    pressed[k]       := false
    pulseActive[k]   := false
    nextPulseTime[k] := 0
    offTime[k]       := 0
}

; ── Funciones auxiliares ────────────────────────────────
Turbo(name, wantPressed) {
    if (name = "LT" || name = "RT") {
        controller.Axes[name].SetState(wantPressed ? 255 : 0)
    } else {
        controller.Buttons[name].SetState(wantPressed ? 1 : 0)
    }
}

; ── Timer principal ─────────────────────────────────────
SetTimer CheckController, 8

CheckController() {
    static lastReportTime := 0
    static port := -1

    ; Buscar puerto del mando solo la primera vez
    if (port = -1) {
        loop 4 {
            if (XInput_GetState(A_Index-1) && XInput_GetState(A_Index-1).dwPacketNumber > 0) {
                port := A_Index-1
                break
            }
        }
        if (port = -1)
            return  ; no hay mando → salir
    }

    state := XInput_GetState(port)
    if (!state || !state.dwPacketNumber)
        return

    currentTime := A_TickCount

    ; ── Botones digitales ───────────────────────────────
    for btn, mask in BUTTONS {
        now := (state.wButtons & mask) != 0
        interval := (btn = "A" || btn = "Y") ? SLOW_INTERVAL : FAST_INTERVAL
        HandleInput(btn, now, interval, currentTime)
    }

    ; ── Gatillos (triggers) ─────────────────────────────
    HandleInput("LT", state.bLeftTrigger > 30, FAST_INTERVAL, currentTime)
    HandleInput("RT", state.bRightTrigger > 30, FAST_INTERVAL, currentTime)

    ; ── Apagar pulsos que ya cumplieron su duración ─────
    for name, off in offTime {
        if (off > 0 && currentTime >= off) {
            Turbo(name, false)
            pulseActive[name] := false
            offTime[name] := 0
        }
    }

    ; Enviar reporte al ViGEm de forma controlada
    if (currentTime - lastReportTime >= 6) {
        controller.SendReport()
        lastReportTime := currentTime
    }
}

; ── Lógica común para botones y gatillos ───────────────
HandleInput(name, nowPressed, interval, tNow) {
    if (nowPressed) {
        ; Inicio de presión → forzar primer pulso casi inmediato
        if (!pressed[name]) {
            pressed[name] := true
            nextPulseTime[name] := tNow - 5   ; pequeño offset para activar ya
        }

        ; Momento de generar un nuevo pulso
        if (!pulseActive[name] && tNow >= nextPulseTime[name]) {
            Turbo(name, true)
            pulseActive[name] := true
            offTime[name] := tNow + PULSE_HOLD_MS
            nextPulseTime[name] := tNow + interval   ; programar siguiente
        }
    }
    else if (pressed[name]) {
        ; Soltado → apagar inmediatamente y resetear
        pressed[name] := false
        if (pulseActive[name]) {
            Turbo(name, false)
            pulseActive[name] := false
            offTime[name] := 0
        }
        nextPulseTime[name] := 0
    }
}

; ── Limpieza al cerrar el script ────────────────────────
OnExit(*) {
    DllCall("Winmm\timeEndPeriod", "UInt", 1)

    try {
        for btn in ["A","B","X","Y","LB","RB"]
            controller.Buttons[btn].SetState(0)

        controller.Axes["LT"].SetState(0)
        controller.Axes["RT"].SetState(0)

        controller.SendReport()
    }

    ExitApp
}