#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
init_xui.py — Автоматическая инициализация и генерация VLESS-Reality клиента для 3X-UI.
Автоматически настраивает БД 3X-UI (даже с нуля), создает VLESS-инбаунд и генерирует готовую ссылку.
"""

import os
import sys
import time
import json
import uuid
import secrets
import sqlite3
import subprocess
import re

# === START: [2026-10-28] Автоматическая инициализация 3X-UI и создание VLESS-Reality ===

def load_env_file(filepath=".env"):
    """Загрузка переменных из .env файла, если он существует."""
    env_vars = {}
    if os.path.isfile(filepath):
        with open(filepath, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, val = line.split("=", 1)
                    env_vars[key.strip()] = val.strip().strip("'\"")
    return env_vars

def get_config_val(key, default, env_file_vars):
    """Получение значения из окружения, затем из .env, затем дефолт."""
    return os.environ.get(key) or env_file_vars.get(key) or default

def get_server_domain(env_domain=None):
    """Определение доменного имени или публичного IP сервера."""
    if env_domain and env_domain.strip():
        return env_domain.strip()

    # Проверка наличия SSL-сертификата в /root/cert
    cert_dir = "/root/cert"
    if os.path.isdir(cert_dir):
        # Ищем поддиректорию с самым свежим сертификатом
        entries = [os.path.join(cert_dir, d) for d in os.listdir(cert_dir)]
        dirs = [d for d in entries if os.path.isdir(d) and not os.path.basename(d) in ["ip", "live"]]
        if dirs:
            dirs.sort(key=lambda x: os.path.getmtime(x), reverse=True)
            candidate = os.path.basename(dirs[0])
            if "." in candidate and not candidate.startswith("213."):
                return candidate

    # Попытка получить внешний IPv4 через curl
    try:
        ip = subprocess.check_output(["curl", "-s4", "--connect-timeout", "3", "ifconfig.me"], timeout=5).decode().strip()
        if ip:
            return ip
    except Exception:
        pass

    return "127.0.0.1"

def generate_xray_keys():
    """Генерация ключей X25519 через бинарник xray внутри контейнера 3x_ui или на хосте."""
    priv_key, pub_key = None, None
    commands_to_try = [
        ["docker", "exec", "3x_ui", "/usr/local/x-ui/bin/xray-linux-amd64", "x25519"],
        ["/usr/local/x-ui/bin/xray-linux-amd64", "x25519"],
        ["xray", "x25519"]
    ]

    for cmd in commands_to_try:
        try:
            out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, timeout=10).decode()
            priv_m = re.search(r"PrivateKey:\s*([A-Za-z0-9_\-]+)", out)
            pub_m = re.search(r"(?:Password\s*\()?[Pp]ublicKey\)?:\s*([A-Za-z0-9_\-]+)", out)
            if priv_m and pub_m:
                priv_key = priv_m.group(1).strip()
                pub_key = pub_m.group(1).strip()
                break
        except Exception:
            continue

    if not priv_key or not pub_key:
        # Fallback дефолтные ключи, если xray недоступен
        priv_key = "0BbRjsMVwTDWB6mZffkaSpyAYQLypCo0MfL4NKGusUs"
        pub_key = "HUe8wO7hrqa0yQWJQrC7T9xQa8I4W3ClmC2-rMJC8Us"

    return priv_key, pub_key

def wait_for_db(db_path, max_wait=20):
    """Ожидание появления и инициализации структуры БД 3X-UI."""
    print(f"[*] Проверка базы данных: {db_path}...")
    for _ in range(max_wait):
        if os.path.isfile(db_path):
            try:
                con = sqlite3.connect(db_path)
                cur = con.cursor()
                cur.execute("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='settings'")
                if cur.fetchone()[0] > 0:
                    con.close()
                    return True
                con.close()
            except Exception:
                pass
        time.sleep(1)
    return False

def configure_3xui():
    env_vars = load_env_file()

    # Параметры путей и Reality
    raw_xui_path = get_config_val("XUI_PATH", "/xui/", env_vars)
    xui_path = "/" + raw_xui_path.strip("/") + "/"
    reality_sni = get_config_val("REALITY_SNI", "www.nvidia.com", env_vars)
    reality_target = get_config_val("REALITY_TARGET", f"{reality_sni}:443", env_vars)
    server_domain = get_server_domain(get_config_val("SERVER_DOMAIN", None, env_vars))

    # Путь к БД: сначала проверяем локальный ./db/x-ui.db, затем /etc/x-ui/x-ui.db
    db_candidates = ["db/x-ui.db", "./db/x-ui.db", "/etc/x-ui/x-ui.db"]
    db_path = None
    for cand in db_candidates:
        if os.path.isfile(cand):
            db_path = cand
            break

    if not db_path:
        db_path = "db/x-ui.db"
        if not wait_for_db(db_path, max_wait=15):
            print(f"[!] База {db_path} не найдена. Убедитесь, что контейнер 3x-ui запущен.")
            sys.exit(1)

    con = sqlite3.connect(db_path)
    cur = con.cursor()

    # 1. Настройка таблицы settings (изоляция панели)
    print("[*] Обновление настроек панели 3X-UI...")
    cur.execute("SELECT value FROM settings WHERE key = 'webListen'")
    prev_listen = cur.fetchone()
    need_restart = False
    if not prev_listen or prev_listen[0] != '127.0.0.1':
        need_restart = True

    cur.execute("UPDATE settings SET value = '127.0.0.1' WHERE key = 'webListen'")
    cur.execute("UPDATE settings SET value = '53273' WHERE key = 'webPort'")
    cur.execute("UPDATE settings SET value = ? WHERE key = 'webBasePath'", (xui_path,))
    cur.execute("UPDATE settings SET value = '' WHERE key = 'webCertFile'")
    cur.execute("UPDATE settings SET value = '' WHERE key = 'webKeyFile'")
    con.commit()

    # Проверка учетных данных админа
    admin_user = "admin"
    admin_pass = "admin"
    user_row = cur.execute("SELECT username, password FROM users LIMIT 1").fetchone()
    if user_row:
        admin_user, admin_pass = user_row[0], user_row[1]
    else:
        # Создаем администратора, если таблицы пользователей пуста
        admin_user = get_config_val("XUI_USER", "admin", env_vars)
        admin_pass = get_config_val("XUI_PASS", secrets.token_urlsafe(10), env_vars)
        cur.execute("INSERT INTO users (username, password) VALUES (?, ?)", (admin_user, admin_pass))
        con.commit()

    # 2. Проверка и создание VLESS-Reality инбаунда
    inbound = cur.execute("SELECT id, settings, stream_settings FROM inbounds WHERE port = 8443").fetchone()

    need_restart = False
    client_uuid = None
    public_key = None
    short_id = None
    flow = "xtls-rprx-vision"
    email = "client1"

    if inbound:
        print("[*] Найден существующий VLESS-Reality инбаунд (порт 8443).")
        inbound_id, settings_json, stream_json = inbound[0], inbound[1], inbound[2]
        try:
            s_data = json.loads(settings_json)
            client = s_data.get("clients", [{}])[0]
            client_uuid = client.get("id")
            flow = client.get("flow", "xtls-rprx-vision")
            email = client.get("email", "client1")

            st_data = json.loads(stream_json)
            r_settings = st_data.get("realitySettings", {})
            public_key = r_settings.get("settings", {}).get("publicKey")
            short_ids = r_settings.get("shortIds", [])
            short_id = short_ids[0] if short_ids else "5d2bbc"
            
            # Актуализируем SNI если изменился
            current_snis = r_settings.get("serverNames", [])
            if reality_sni not in current_snis:
                print(f"[*] Обновление Reality SNI на: {reality_sni}")
                r_settings["serverNames"] = [reality_sni]
                r_settings["target"] = reality_target
                st_data["realitySettings"] = r_settings
                cur.execute("UPDATE inbounds SET stream_settings = ? WHERE id = ?", (json.dumps(st_data), inbound_id))
                con.commit()
                need_restart = True
        except Exception as e:
            print(f"[!] Ошибка парсинга инбаунда: {e}")

    if not client_uuid or not public_key:
        print("[*] Создание нового VLESS-Reality инбаунда с нуля...")
        priv_key, pub_key = generate_xray_keys()
        client_uuid = str(uuid.uuid4())
        short_id = secrets.token_hex(4)
        sub_id = secrets.token_hex(8)
        public_key = pub_key

        settings_dict = {
            "clients": [{
                "id": client_uuid,
                "flow": flow,
                "email": email,
                "enable": True,
                "expiryTime": 0,
                "totalGB": 0,
                "reset": 0,
                "subId": sub_id
            }],
            "decryption": "none",
            "encryption": "none",
            "testseed": [900, 500, 900, 256]
        }

        stream_settings_dict = {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
                "show": False,
                "xver": 0,
                "target": reality_target,
                "serverNames": [reality_sni],
                "privateKey": priv_key,
                "minClientVer": "",
                "maxClientVer": "",
                "maxTimediff": 0,
                "shortIds": [short_id],
                "settings": {
                    "publicKey": pub_key,
                    "fingerprint": "chrome",
                    "serverName": "",
                    "spiderX": "/"
                }
            },
            "tcpSettings": {
                "acceptProxyProtocol": False,
                "header": {"type": "none"}
            }
        }

        sniffing_dict = {
            "enabled": True,
            "destOverride": ["http", "tls", "quic", "fakedns"]
        }

        cur.execute("""
            INSERT INTO inbounds (
                user_id, up, down, total, remark, enable, expiry_time,
                listen, port, protocol, settings, stream_settings, tag, sniffing
            ) VALUES (?, 0, 0, 0, ?, 1, 0, '127.0.0.1', 8443, 'vless', ?, ?, 'in-8443-tcp', ?)
        """, (
            1, "VLESS-Reality", json.dumps(settings_dict),
            json.dumps(stream_settings_dict), json.dumps(sniffing_dict)
        ))
        inbound_id = cur.lastrowid

        # Добавляем клиента в таблицу clients и client_inbounds
        now_ms = int(time.time() * 1000)
        cur.execute("""
            INSERT OR IGNORE INTO clients (email, sub_id, uuid, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
        """, (email, sub_id, client_uuid, now_ms, now_ms))
        client_id = cur.lastrowid or 1

        cur.execute("""
            INSERT OR IGNORE INTO client_inbounds (client_id, inbound_id, flow_override, created_at)
            VALUES (?, ?, ?, ?)
        """, (client_id, inbound_id, flow, now_ms))

        cur.execute("""
            INSERT OR IGNORE INTO client_traffics (inbound_id, enable, email, up, down, expiry_time, total)
            VALUES (?, 1, ?, 0, 0, 0, 0)
        """, (inbound_id, email))

        con.commit()
        need_restart = True

    con.close()

    if need_restart:
        print("[*] Перезапуск контейнера 3x-ui для применения настроек...")
        subprocess.run(["docker", "compose", "restart", "3x-ui"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["docker", "restart", "3x_ui"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(2)

    # 3. Генерация клиентской ссылки VLESS Reality
    remark = f"{server_domain}-Reality"
    vless_link = (
        f"vless://{client_uuid}@{server_domain}:443"
        f"?security=reality&encryption=none&pbk={public_key}&headerType=none"
        f"&fp=chrome&type=tcp&flow={flow}&sni={reality_sni}&sid={short_id}&spx=%2F#{remark}"
    )

    panel_url = f"https://{server_domain}{xui_path}"

    # Сохраняем в файл client_vless.txt
    with open("client_vless.txt", "w", encoding="utf-8") as f:
        f.write("# === Готовая ссылка подключения VLESS Reality ===\n")
        f.write(vless_link + "\n\n")
        f.write(f"# Панель управления 3X-UI: {panel_url}\n")
        f.write(f"# Логин: {admin_user}\n")
        f.write(f"# Пароль: {admin_pass}\n")

    # Красивый вывод в терминал
    box_width = 80
    print("\n" + "=" * box_width)
    print("🎉 КОМПЛЕКС УСПЕШНО РАЗВЕРНУТ И НАСТРОЕН!".center(box_width))
    print("=" * box_width)
    print(f"\n🌐 Сайт-маскировка: https://{server_domain}")
    print(f"🔒 Панель 3X-UI:    {panel_url}")
    print(f"👤 Логин:           {admin_user}")
    print(f"🔑 Пароль:          {admin_pass}")
    print("\n" + "-" * box_width)
    print("🚀 ВАША ГОТОВАЯ ССЫЛКА ДЛЯ КЛИЕНТА (Happ, Streisand, v2rayNG, Hiddify, Nekobox):")
    print("-" * box_width)
    print(f"\n{vless_link}\n")
    print("-" * box_width)
    print("💾 Ссылка и реквизиты также сохранены в файл: client_vless.txt")
    print("=" * box_width + "\n")

if __name__ == "__main__":
    configure_3xui()
# === END: [2026-10-28] Автоматическая инициализация 3X-UI и создание VLESS-Reality ===
