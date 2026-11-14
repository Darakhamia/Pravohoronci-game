"""Пересобирает весь «вид» станции одной командой: текстуры, декали, библиотеку материалов и замены в импорте.

Запуск из корня репозитория:
    python3 tools/textures/build.py
    godot --headless --import            # после этого Godot переимпортирует текстуры и модели

По шагам (каждый можно запустить отдельно):
1. make_textures.py  — плиточные PBR-наборы assets/textures/surfaces/*.png (+ .import);
2. make_decals.py    — текстуры assets/textures/decals/*.png и префабы scenes/maps/decals/*.tscn;
3. apply_materials.py — материалы resources/materials/*.tres (и world/*.tres) и секция _subresources во всех
   assets/models/kit/*.glb.import и assets/models/props/*.glb.import.

Если менялись сами модели (tools/assets/kit.py, props.py), сначала пересобери их в Blender и один раз выполни
godot --headless --import, чтобы у новых .glb появились файлы .import, — и только потом запускай этот скрипт.
Результат детерминирован: повторный запуск без правок даёт те же файлы.
"""

import os
import subprocess
import sys

STEPS = ("make_textures.py", "make_decals.py", "apply_materials.py")


def main():
    folder = os.path.dirname(os.path.abspath(__file__))
    for step in STEPS:
        print("==", step)
        result = subprocess.run([sys.executable, os.path.join(folder, step)], check=False)
        if result.returncode != 0:
            print("ОШИБКА: шаг %s завершился с кодом %d" % (step, result.returncode))
            return result.returncode
    print("Готово. Теперь: godot --headless --import")
    return 0


if __name__ == "__main__":
    sys.exit(main())
