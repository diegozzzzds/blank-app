import sqlite3
from telegram import Update, Chat
from telegram.ext import ApplicationBuilder, CommandHandler, ContextTypes

# 创建数据库
conn = sqlite3.connect('accounting_bot.db', check_same_thread=False)
c = conn.cursor()

# 创建表
c.execute('''CREATE TABLE IF NOT EXISTS operators (username TEXT)''')
c.execute('''CREATE TABLE IF NOT EXISTS rates (rate_type TEXT, value REAL)''')
c.execute('''CREATE TABLE IF NOT EXISTS transactions (id INTEGER PRIMARY KEY, type TEXT, amount REAL, currency TEXT)''')
conn.commit()

# 仅在群组中响应命令
async def handle_group_only(update: Update, context: ContextTypes.DEFAULT_TYPE) -> bool:
    if update.message.chat.type != Chat.GROUP and update.message.chat.type != Chat.SUPERGROUP:
        await update.message.reply_text("xxxxxxx，完全免费使用，如果觉得方便，请推荐给朋友们！ 如果机器人异常，请t出群重新拉就好了。机器人使用说明: xxxxxxx")
        return False
    return True

# 添加操作人
async def set_operator(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await handle_group_only(update, context):
        return

    if context.args:
        operator = context.args[0]
        c.execute("INSERT INTO operators (username) VALUES (?)", (operator,))
        conn.commit()
        await update.message.reply_text(f"操作人 {operator} 已设置。")
    else:
        await update.message.reply_text("命令格式：设置操作人 @xxx")

# 设置费率
async def set_rate(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await handle_group_only(update, context):
        return

    if context.args:
        rate = context.args[0]
        c.execute("INSERT OR REPLACE INTO rates (rate_type, value) VALUES (?, ?)", ('rate', rate))
        conn.commit()
        await update.message.reply_text(f"费率已设置为 {rate}%。")
    else:
        await update.message.reply_text("命令格式：设置费率x%")

# 设置汇率
async def set_exchange_rate(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await handle_group_only(update, context):
        return

    if context.args:
        exchange_rate = context.args[0]
        c.execute("INSERT OR REPLACE INTO rates (rate_type, value) VALUES (?, ?)", ('exchange_rate', exchange_rate))
        conn.commit()
        await update.message.reply_text(f"汇率已设置为 {exchange_rate}。")
    else:
        await update.message.reply_text("命令格式：设置汇率x.xx")

# 开始记账
async def start_accounting(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await handle_group_only(update, context):
        return

    await update.message.reply_text("记账已开始，费率和汇率已锁定。")

# 显示操作人
async def show_operators(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await handle_group_only(update, context):
        return

    c.execute("SELECT username FROM operators")
    operators = c.fetchall()
    if operators:
        operator_list = "\n".join([op[0] for op in operators])
        await update.message.reply_text(f"操作人列表:\n{operator_list}")
    else:
        await update.message.reply_text("当前没有设置操作人。")

# 入款
async def deposit(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await handle_group_only(update, context):
        return

    if context.args:
        amount = context.args[0]
        c.execute("INSERT INTO transactions (type, amount, currency) VALUES (?, ?, ?)", ('deposit', amount, 'U'))
        conn.commit()
        await update.message.reply_text(f"已记录入款：{amount} U。")
    else:
        await update.message.reply_text("命令格式：入款+xxx")

# 下发
async def payout(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await handle_group_only(update, context):
        return

    if context.args:
        amount = context.args[0]
        currency = 'U' if 'U' in amount.upper() else '美'
        c.execute("INSERT INTO transactions (type, amount, currency) VALUES (?, ?, ?)", ('payout', amount, currency))
        conn.commit()
        await update.message.reply_text(f"已记录下发：{amount} {currency}。")
    else:
        await update.message.reply_text("命令格式：下发xxxU 或 下发xxx美")

# 显示账单
async def show_transactions(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await handle_group_only(update, context):
        return

    c.execute("SELECT type, amount, currency FROM transactions ORDER BY id DESC LIMIT 3")
    transactions = c.fetchall()
    if transactions:
        transaction_list = "\n".join([f"{t[0]}: {t[1]} {t[2]}" for t in transactions])
        await update.message.reply_text(f"最近三笔交易：\n{transaction_list}")
    else:
        await update.message.reply_text("没有记录任何交易。")

# 删除账单
async def delete_transactions(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await handle_group_only(update, context):
        return

    c.execute("DELETE FROM transactions")
    conn.commit()
    await update.message.reply_text("所有账单已删除。")

# 主函数，启动机器人
async def main() -> None:
    app = ApplicationBuilder().token('8126969786:AAGzYMfpnIM0UrVtUW0asXrfOg-ZS5sJwUc').build()

    app.add_handler(CommandHandler("设置操作人", set_operator))
    app.add_handler(CommandHandler("设置费率", set_rate))
    app.add_handler(CommandHandler("设置汇率", set_exchange_rate))
    app.add_handler(CommandHandler("开始记账", start_accounting))
    app.add_handler(CommandHandler("入款", deposit))
    app.add_handler(CommandHandler("下发", payout))
    app.add_handler(CommandHandler("显示账单", show_transactions))
    app.add_handler(CommandHandler("",
