from flask import Flask, jsonify, request, render_template, redirect, url_for, session
from flask_socketio import SocketIO, emit
from flask_session import Session
import threading
import requests
import time
import random
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask(__name__)
app.secret_key = 'supersecretkey'
app.config['SESSION_TYPE'] = 'filesystem'
Session(app)
socketio = SocketIO(app)

test_status = {}
history = []
users = {}  # 使用字典存储用户数据

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.121 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0.1 Safari/605.1.15",
    "Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.75 Mobile Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1",
]

def generate_progress(url, num_requests, num_threads, attack_time, attack_mode):
    response_times = []
    test_status['total_requests'] = num_requests
    test_status['successful_requests'] = 0
    test_status['failed_requests'] = 0
    test_status['start_time'] = time.time()

    def send_request():
        nonlocal response_times
        end_time = time.time() + attack_time
        
        while time.time() < end_time and test_status['successful_requests'] + test_status['failed_requests'] < num_requests:
            try:
                if attack_mode == 'get':
                    start_time = time.time()
                    response = requests.get(url, headers={"User-Agent": random.choice(USER_AGENTS)}, timeout=5)
                    response_times.append(time.time() - start_time)
                elif attack_mode == 'post':
                    start_time = time.time()
                    response = requests.post(url, headers={"User-Agent": random.choice(USER_AGENTS)}, timeout=5)
                    response_times.append(time.time() - start_time)
                elif attack_mode == 'slowloris':
                    for i in range(5):
                        requests.get(url, headers={"User-Agent": random.choice(USER_AGENTS)}, timeout=5)
                        time.sleep(1)

                test_status['successful_requests'] += 1
            except Exception:
                response_times.append(None)
                test_status['failed_requests'] += 1
            
            socketio.emit('status_update', {
                "total_requests": test_status['total_requests'],
                "successful_requests": test_status['successful_requests'],
                "failed_requests": test_status['failed_requests'],
                "elapsed_time": time.time() - test_status['start_time'],
                "average_time": (sum(filter(None, response_times)) / len(response_times)) if response_times else 0
            })

    threads = []
    for _ in range(num_threads):
        thread = threading.Thread(target=send_request)
        threads.append(thread)
        thread.start()

    for thread in threads:
        thread.join()

    history.append({
        "url": url,
        "num_requests": num_requests,
        "successful_requests": test_status['successful_requests'],
        "failed_requests": test_status['failed_requests'],
        "elapsed_time": time.time() - test_status['start_time'],
        "attack_time": attack_time,
        "attack_mode": attack_mode,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
    })

@app.route('/load-test', methods=['POST'])
def load_test():
    if not session.get('username'):
        return jsonify({"message": "未登录!"}), 403
    
    data = request.json
    url = data.get('url')
    num_requests = data.get('num_requests', 100)
    num_threads = data.get('num_threads', 10)
    attack_time = data.get('attack_time', 10)
    attack_mode = data.get('attack_mode', 'get')

    generate_progress(url, num_requests, num_threads, attack_time, attack_mode)
    return jsonify({"message": "加载测试已启动!"}), 200

@app.route('/api/load-test', methods=['POST'])
def api_load_test():
    """API接口，允许登录用户发起负载测试"""
    username = request.headers.get('X-Username')
    password = request.headers.get('X-Password')

    # 简单的用户验证
    if username not in users or not check_password_hash(users[username], password):
        return jsonify({"message": "未授权"}), 401

    data = request.json
    url = data.get('url')
    num_requests = data.get('num_requests', 100)
    num_threads = data.get('num_threads', 10)
    attack_time = data.get('attack_time', 10)
    attack_mode = data.get('attack_mode', 'get')

    threading.Thread(target=generate_progress, args=(url, num_requests, num_threads, attack_time, attack_mode)).start()
    return jsonify({"message": "API加载测试已启动!"}), 200

@app.route('/history', methods=['GET'])
def get_history():
    return jsonify(history), 200

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/admin')
def admin():
    if not session.get('username'):
        return redirect(url_for('login'))
    return render_template('admin.html')

@app.route('/register', methods=['POST'])
def register():
    data = request.json
    username = data.get('username')
    password = data.get('password')

    if username in users:
        return jsonify({"message": "用户已存在!"}), 400
    
    users[username] = generate_password_hash(password)
    return jsonify({"message": "注册成功!"}), 201

@app.route('/login', methods=['POST'])
def login():
    data = request.json
    username = data.get('username')
    password = data.get('password')

    if username not in users or not check_password_hash(users[username], password):
        return jsonify({"message": "用户名或密码错误!"}), 403

    session['username'] = username
    return jsonify({"message": "登录成功!"}), 200

@app.route('/logout', methods=['POST'])
def logout():
    session.pop('username', None)
    return jsonify({"message": "注销成功!"}), 200

@socketio.on('connect')
def handle_connect():
    emit('response', {'message': '客户端已连接'})

if __name__ == '__main__':
    socketio.run(app, debug=True)