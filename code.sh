#!/bin/bash
# Mise à jour et installation des paquets AL2023
dnf update -y
dnf install -y python3-pip

# Installation de Flask et PyMySQL
pip3 install flask pymysql

cat << 'EOT' > /home/ec2-user/app.py
from flask import Flask
import pymysql
import os

app = Flask(__name__)

DB_HOST = os.getenv("DB_HOST", "${db_host}")
DB_USER = os.getenv("DB_USER", "${db_user}")
DB_PASSWORD = os.getenv("DB_PASSWORD", "${db_password}")
DB_NAME = os.getenv("DB_NAME", "${db_name}")

@app.route("/")
def check_db():
    try:
        connection = pymysql.connect(
            host=DB_HOST, user=DB_USER, password=DB_PASSWORD, database=DB_NAME,
            cursorclass=pymysql.cursors.DictCursor
        )
        with connection.cursor() as cursor:
            cursor.execute("SELECT VERSION() AS version;")
            result = cursor.fetchone()
        connection.close()
        return f"<h1>Terraform Test Success!</h1><p>Connected to MySQL. Version: {result['version']}</p>"
    except Exception as e:
        return f"<h1>Database Connection Failed</h1><p>{str(e)}</p>", 500

@app.route("/health")
def health_check():
    return "OK", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOT

cd /home/ec2-user
nohup python3 app.py > app.log 2>&1 &