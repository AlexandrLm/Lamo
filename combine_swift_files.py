#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Скрипт для объединения всех Swift файлов в один txt файл
"""

import os
from pathlib import Path

# Настройки
OUTPUT_FILE = "all_swift_files.txt"
PROJECT_DIR = "Lamo"

def find_swift_files(directory):
    """Находит все .swift файлы в указанной директории"""
    swift_files = []
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.swift'):
                swift_files.append(os.path.join(root, file))
    return sorted(swift_files)

def combine_swift_files():
    """Объединяет все Swift файлы в один txt файл"""
    # Удаляем старый файл, если существует
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    
    # Находим все Swift файлы
    swift_files = find_swift_files(PROJECT_DIR)
    
    if not swift_files:
        print(f"Swift файлы не найдены в директории {PROJECT_DIR}")
        return
    
    # Записываем все файлы в выходной файл
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as outfile:
        for swift_file in swift_files:
            # Добавляем разделитель с именем файла
            outfile.write("=" * 80 + "\n")
            outfile.write(f"Файл: {swift_file}\n")
            outfile.write("=" * 80 + "\n\n")
            
            # Читаем и записываем содержимое файла
            try:
                with open(swift_file, 'r', encoding='utf-8') as infile:
                    outfile.write(infile.read())
                outfile.write("\n\n")
            except Exception as e:
                outfile.write(f"Ошибка при чтении файла: {e}\n\n")
    
    print(f"Готово! Найдено {len(swift_files)} Swift файлов")
    print(f"Все файлы объединены в {OUTPUT_FILE}")

if __name__ == "__main__":
    combine_swift_files()

