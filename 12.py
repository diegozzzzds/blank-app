import re
import logging
import requests
from bs4 import BeautifulSoup
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, MessageHandler, filters, ContextTypes, CallbackQueryHandler
import asyncio
import nest_asyncio
from datetime import datetime
import pandas as pd  # Make sure to install pandas
import os
from functools import wraps

# Configure logging
logging.basicConfig(
    format="%(asctime)s - %(levelname)s - %(message)s",
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# Token
TOKEN = "8126969786:AAGzYMfpnIM0UrVtUW0asXrfOg-ZS5sJwUc"  # Make sure to use a safe way to handle your token

# Initialize variables
unremovable_operator_id = 7191837720  # Constant for the unremovable operator user ID
operator_user_ids = [7191837720,]  # List to store operator user IDs, including the unremovable one
allowed_group_ids = [-4507680496]  # List of allowed group IDs that your bot can operate in
rate = -50
fixed_rate = 7.4
usd_rate = 7.0
total_in = 0
total_out_amount = 0
transactions = []
withdrawals = []
user_data = {}
group_data = {}
current_date = datetime.now().date()

# Dictionary to store group-specific transactions
group_transactions = {}

# Function to reset today's transactions
def reset_daily_totals():
    global total_in, total_out_amount, transactions, withdrawals, current_date
    if datetime.now().date() != current_date:
        logger.info("Resetting daily totals for a new day.")
        total_in = 0
        total_out_amount = 0
        transactions = []
        withdrawals = []
        current_date = datetime.now().date()

# Escape Markdown characters
def escape_markdown(text):
    return re.sub(r'([_*\[\]()~>#+\-=|{}.!])', r'\\\1', text)

# Check if user is banned
def is_banned(user_id):
    return user_data.get(user_id, {}).get("banned", False)

# Check if user is authorized (based on user IDs)
async def is_authorized(user_id: int):
    return user_id in operator_user_ids

# Decorator for checking operator authorization
def operator_required(func):
    @wraps(func)
    async def wrapper(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not await is_authorized(update.effective_user.id):
            await update.message.reply_text
            return
        return await func(update, context)
    return wrapper

# Function to check group membership
async def check_group(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat = update.effective_chat
    if chat.type != 'private':
        if chat.id not in allowed_group_ids:
            await update.message.reply_text("您不在授权的群组内，机器人将退出此群组。")
            await context.bot.leave_chat(chat.id)
            logger.info(f"Bot left group: {chat.id}")
            return False
    return True

# Function to calculate total amount for a specific group
def calculate_total_amount(group_id):
    total_amount = 0
    if group_id in group_transactions:
        for transaction in group_transactions[group_id]:
            total_amount += transaction.get('amount', 0)
    return total_amount

# Function to calculate today's total for the current group
def calculate_todays_total(group_id):
    todays_total = 0
    if group_id in group_transactions:
        for transaction in group_transactions[group_id]:
            if transaction.get('time')[:10] == datetime.now().date().strftime('%Y-%m-%d'):
                todays_total += transaction.get('amount', 0)
    return todays_total

# Fetch top 10 USDT prices for CNY
async def fetch_top_usdt_prices():
    url = "https://www.okx.com/zh-hans/p2p-markets/cny/buy-usdt"
    headers = {"User-Agent": "Mozilla/5.0"}
    prices = []

    try: 
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        logger.info("Fetched USDT price page successfully.")

        soup = BeautifulSoup(response.text, 'html.parser')
        price_elements = soup.select('span.price')
        merchant_elements = soup.select('span.merchant-name-section a.Tags_merchantLink__u5a8b')

        logger.info(f"Found {len(price_elements)} price elements and {len(merchant_elements)} merchant elements.")

        for price_element, merchant_element in zip(price_elements, merchant_elements):
            price_text = price_element.text.strip().replace(' CNY', '').replace('元', '').strip()
            merchant_name = merchant_element.text.strip()
            try:
                prices.append((float(price_text), merchant_name))
            except ValueError:
                logger.warning(f"Failed to convert '{price_text}' to float.")
                continue

        if not prices:
            logger.info("No valid USDT prices found.")
            return []

        top_prices = sorted(prices)[:10]
        return top_prices

    except Exception as e:
        logger.error(f"Error fetching USDT prices: {e}")
        return []

# Command handler for USDT price
async def handle_usdt_price(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_group(update, context):
        return
    reset_daily_totals()
    
    top_prices = await fetch_top_usdt_prices()
    if top_prices:
        response_lines = [
            f"{i + 1}. {price:.2f}元 ({merchant_name})"
            for i, (price, merchant_name) in enumerate(top_prices)
        ]
        await update.message.reply_text("\n".join(response_lines))
    else:
        await update.message.reply_text("无法获取USDT价格，请稍后再试。")

# Command handler for conversion
async def handle_conversion(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_group(update, context):
        return
    reset_daily_totals()
    try:
        amount_cny = float(re.findall(r'\d+', update.message.text)[0])
        top_prices = await fetch_top_usdt_prices()

        if top_prices:
            response_lines = []
            for price_per_usdt, merchant_name in top_prices:
                result = amount_cny / price_per_usdt
                response_lines.append(
                    f"🔹 {amount_cny:.2f}元 / {price_per_usdt:.2f}元 ({merchant_name}) = {result:.2f} USDT"
                )

            response = "\n".join(response_lines)
            await update.message.reply_text(response)
        else:
            await update.message.reply_text("无法进行转换，未找到有效价格。")

    except (IndexError, ValueError):
        await update.message.reply_text("请提供有效的CNY金额，例如：z1（1 CNY）。")

# Command handler for income
@operator_required
async def handle_income(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_group(update, context):
        return
    global total_in, transactions
    reset_daily_totals()

    try:
        amount = float(update.message.text[1:].strip())
        total_in += amount
        transactions.append((amount, datetime.now()))

        # Save transaction for the group
        group_id = update.effective_chat.id
        save_transaction(group_id, amount, datetime.now(), is_income=True)

        await display_summary(update)
    except (IndexError, ValueError) as e:
        await update.message.reply_text("请提供有效的入款金额，例如：+5000。")
        logger.error(f"Error processing income: {e}")

# Command handler for withdrawal
@operator_required
async def handle_withdrawal(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_group(update, context):
        return
    global total_out_amount, withdrawals
    reset_daily_totals()

    text = update.message.text.strip()

    try:
        amount = float(re.findall(r'\d+', text)[0])

        if text.endswith('C'):
            total_out_amount += amount
            withdrawals.append((amount, datetime.now()))
            group_id = update.effective_chat.id
            save_transaction(group_id, amount, datetime.now(), is_income=False)
            await update.message.reply_text(f"已成功下发 {amount} CNY。")
        elif text.endswith('U'):
            total_out_amount += amount * fixed_rate
            withdrawals.append((amount, datetime.now()))
            group_id = update.effective_chat.id
            save_transaction(group_id, amount * fixed_rate, datetime.now(), is_income=False)
            await update.message.reply_text(f"已成功下发 {amount} USDT。")
        else:
            await update.message.reply_text("请使用格式：下发xxxC 或 下发xxxU")
            return

        await display_summary(update)
    except (IndexError, ValueError):
        await update.message.reply_text("请提供有效的下发金额，例如：下发50C 或 下发50U。")

# Function to save transactions to group-specific data structure
def save_transaction(group_id, amount, transaction_time, is_income):
    if group_id not in group_transactions:
        group_transactions[group_id] = []
    group_transactions[group_id].append({
        "amount": amount,
        "time": transaction_time.strftime('%Y-%m-%d %H:%M:%S'),
        "type": "income" if is_income else "withdrawal"
    })

# Display summary
async def display_summary(update: Update):
    global total_in, total_out_amount, transactions, withdrawals
    total_out = total_out_amount

    recent_deposits = transactions[-3:]
    recent_withdrawals = withdrawals[-3:]

    recent_deposit_display = "\n".join([
        f"{time.strftime('%H:%M:%S')} {amount:.2f} / {fixed_rate:.2f}={amount / fixed_rate:.2f}" 
        for (amount, time) in recent_deposits
    ])

    recent_withdrawal_display = "\n".join([
        f"{time.strftime('%H:%M:%S')} {amount:.2f}"
        for (amount, time) in recent_withdrawals
    ])

    keyboard = [
        [InlineKeyboardButton("咨询群老板", url='https://t.me/likezhuangyuan')],
        [InlineKeyboardButton("自助兑换", url='https://t.me/likezhuangyuan'),
         InlineKeyboardButton("完整账单", url='https://t.me/likezhuangyuan')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    response = (
        f"✨ *今日账单* ✨\n\n"
        f"已入款（{len(transactions)}笔）：\n"
        f"{recent_deposit_display or '无记录'}\n\n"
        f"已下发（{len(withdrawals)}笔）：\n"
        f"{recent_withdrawal_display or '无记录'}\n\n"
        f"总入款金额：{total_in:.2f}\n"
        f"费率：{rate:.1f}%\n"
        f"固定汇率：{fixed_rate:.2f}\n"
        f"应下发：{total_in:.2f} | {total_in / fixed_rate:.2f} (USDT)\n"
        f"已下发：{total_out:.2f} | {total_out / fixed_rate:.2f} (USDT)\n"
        f"未下发：{(total_in - total_out):.2f}CNY | {((total_in - total_out) / fixed_rate):.2f} (USDT)"
    )

    await update.message.reply_text(escape_markdown(response), reply_markup=reply_markup, parse_mode="MarkdownV2")

# Display history bill
async def display_history_bill(update: Update):
    global total_in, total_out_amount, transactions, withdrawals
    
    total_out = total_out_amount  
    historical_total_amount = calculate_total_amount(update.effective_chat.id)
    todays_total = calculate_todays_total(update.effective_chat.id)

    recent_deposits = transactions[-3:]
    recent_withdrawals = withdrawals[-3:]

    recent_deposit_display = "\n".join([
        f"第{i + 1}笔: {amount:.2f} (时间: {time.strftime('%Y-%m-%d %H:%M:%S')})"
        for i, (amount, time) in enumerate(recent_deposits)
    ])

    recent_withdrawal_display = "\n".join([
        f"第{i + 1}笔: {amount:.2f}"
        for i, (amount, time) in enumerate(recent_withdrawals)
    ])

    response = (
        f"✨ *历史账单* ✨\n\n"
        f"历史总金额：{total_in:.2f} 元\n"
        f"今日总金额：{todays_total:.2f} 元\n\n"
        f"已入款（{len(transactions)}笔）：\n"
        f"总入款金额：{total_in:.2f}\n"
        f"费率：{rate:.1f}%\n"
        f"固定汇率：{fixed_rate:.2f}\n"
        f"已下发：{total_out:.2f} | {total_out / fixed_rate:.2f} (USDT)\n"
        f"未下发：{total_in - total_out:.2f} | {(total_in / fixed_rate) - (total_out / fixed_rate):.2f} (USDT)\n\n"
        f"最大3条入款记录：\n{recent_deposit_display or '无记录'}\n\n"
        f"最大3条下发记录：\n{recent_withdrawal_display or '无记录'}"
    )

    await update.message.reply_text(escape_markdown(response), parse_mode="MarkdownV2")

# Handle operator setting
@operator_required
async def handle_set_operator(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id

    if context.args and len(context.args) == 1:
        try:
            new_operator_id = int(context.args[0])
            if new_operator_id not in operator_user_ids:
                operator_user_ids.append(new_operator_id)
                await update.message.reply_text(f"操作人 {new_operator_id} 已成功添加。")
                logger.info(f"User {new_operator_id} added as an operator.")
            else:
                await update.message.reply_text("该用户已是操作人。")
        except ValueError:
            await update.message.reply_text("请提供有效的用户ID。")
    else:
        await update.message.reply_text("请使用格式: 设置操作人 <用户ID>。")

# Handle removing an operator
@operator_required
async def handle_remove_operator(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id

    if context.args and len(context.args) == 1:
        try:
            operator_to_remove = int(context.args[0])
            # Check if the operator to remove is the unremovable one
            if operator_to_remove == unremovable_operator_id:
                await update.message.reply_text("该用户是系统操作人，无法被移除。")
                return
            
            if operator_to_remove in operator_user_ids:
                operator_user_ids.remove(operator_to_remove)
                await update.message.reply_text(f"操作人 {operator_to_remove} 已成功移除。")
                logger.info(f"User {operator_to_remove} removed as an operator.")
            else:
                await update.message.reply_text("该用户不是操作人。")
        except ValueError:
            await update.message.reply_text("请提供有效的用户ID。")
    else:
        await update.message.reply_text("请使用格式: 移除操作人 <用户ID>。")

# ... (rest of your code follows)
# Handle rate setting commands
@operator_required
async def handle_rate_setting(update: Update, context: ContextTypes.DEFAULT_TYPE):
    message_text = update.message.text
    global rate, fixed_rate, usd_rate

    if message_text.startswith("设置费率"):
        try:
            rate = float(message_text.split("设置费率")[1].strip("%"))
            await update.message.reply_text(f"费率设置为 {rate}%")
        except (IndexError, ValueError):
            await update.message.reply_text("请提供有效的费率，例如：设置费率 10%")

    elif message_text.startswith("设置汇率"):
        try:
            fixed_rate = float(message_text.split("设置汇率")[1])
            await update.message.reply_text(f"固定汇率设置为 {fixed_rate}")
        except (IndexError, ValueError):
            await update.message.reply_text("请提供有效的汇率")
    
    elif message_text.startswith("设置美元汇率"):
        try:
            usd_rate = float(message_text.split("设置美元汇率")[1])
            await update.message.reply_text(f"美元汇率设置为 {usd_rate}")
        except (IndexError, ValueError):
            await update.message.reply_text("请提供有效的美元汇率")

# Handle text messages
async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    reset_daily_totals()
    
    text = update.message.text.strip()
    logger.info(f"Received command: {text}")

    if is_banned(update.effective_user.id):
        await update.message.reply_text("您已被封禁，误封请找 @likezhuangyuan。")
        return

    if not await check_group(update, context):
        return

    if text.isdigit():  # Check if the text is only digits
        group_id = int(text)
        if group_id in group_transactions:
            await display_history_bill(update)
        else:
            await update.message.reply_text
        return

    if text.startswith("设置操作人"):
        context.args = text.split()[1:]
        await handle_set_operator(update, context)
        return

    if text.startswith("移除操作人"):  # Check for the "remove operator" command
        context.args = text.split()[1:]
        await handle_remove_operator(update, context)  # Call the remove function
        return

    if text.startswith("设置费率") or text.startswith("设置汇率") or text.startswith("设置美元汇率"):
        await handle_rate_setting(update, context)
        return

    # Check authorization and existing commands...
    if text == "显示账单":
        await display_summary(update)

    elif text == "完整账单":
        await display_history_bill(update)

    elif text == "开始记账":
        transactions.clear()
        withdrawals.clear()
        await update.message.reply_text("记账功能已启动")
        logger.info("Accounting started")
        return

    if text.startswith("+"):
        await handle_income(update, context)
    elif text.startswith("下发"):
        await handle_withdrawal(update, context)
    elif text.lower().startswith("z"):
        await handle_conversion(update, context)
    elif text.lower() == "/start":
        await handle_start(update, context)

# Handle /start command
async def handle_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_group(update, context):
        return
    response_message = (
        "某某记账机器人，仅供本团队使用，"
        "有本机器人在群内，均为真群，认准id @xxx 谨防假冒！"
    )

    invite_button = InlineKeyboardButton("点击拉机器人进群", url="https://t.me/Djcnfnfnnrbot?startgroup=config")
    bill_button = InlineKeyboardButton("获取完整账单", callback_data='full_bill')  
    reply_markup = InlineKeyboardMarkup([[invite_button], [bill_button]])  
    
    await update.message.reply_text(response_message, reply_markup=reply_markup)

# Handle callback queries from inline buttons
async def handle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    if query.data == 'full_bill':  
        await display_history_bill(query.message)  

    else:
        await query.edit_message_text(text="你点击了一个按钮！")

# Main function to start the bot
async def main():
    application = Application.builder().token(TOKEN).build()

    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    application.add_handler(MessageHandler(filters.COMMAND, handle_start))
    application.add_handler(CallbackQueryHandler(handle_callback))  

    await application.run_polling()

if __name__ == "__main__":
    nest_asyncio.apply()
    asyncio.run(main())