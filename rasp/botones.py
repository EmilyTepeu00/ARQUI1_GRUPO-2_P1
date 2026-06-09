import RPi.GPIO as GPIO
import config_rasp as cfg

GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)


def inicializar():
    for pin in [cfg.PIN_BTN_MODO, cfg.PIN_BTN_RIEGO,
                cfg.PIN_BTN_LUCES, cfg.PIN_BTN_RESET]:
        GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    print("[BOTONES] GPIO inicializado")


def registrar_todos(cb_modo, cb_riego, cb_luces, cb_reset):
    GPIO.add_event_detect(cfg.PIN_BTN_MODO,  GPIO.FALLING,
                          callback=lambda ch: cb_modo(),  bouncetime=300)
    GPIO.add_event_detect(cfg.PIN_BTN_RIEGO, GPIO.FALLING,
                          callback=lambda ch: cb_riego(), bouncetime=300)
    GPIO.add_event_detect(cfg.PIN_BTN_LUCES, GPIO.FALLING,
                          callback=lambda ch: cb_luces(), bouncetime=300)
    GPIO.add_event_detect(cfg.PIN_BTN_RESET, GPIO.FALLING,
                          callback=lambda ch: cb_reset(), bouncetime=300)
