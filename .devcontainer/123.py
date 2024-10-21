import re
import logging
from telegram import Update, ChatMember
from telegram.ext import Application, MessageHandler, filters, ContextTypes
import asyncio
import nest_asyncio

nest_asyncio.apply()

# Configure logging
logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s", level=logging.INFO
)
logger = logging.getLogger(__name__)

# Token
TOKEN = "8126969786:AAGzYMfpnIM0UrVtUW0asXrfOg-ZS5sJwUc"

# Initialize variables
operator = None
rate = -50
fixed_rate = 7.3
usd_rate = 7.0
total_in = 0
withdrawals = 0
transactions = []
recent_transactions = []  # Keep track of recent transactions for summary
all_users_allowed = False  # Allow all users to use the bot

# Function to escape Markdown characters
def escape_markdown(text):
    return text.replace("_", "\\_").replace("*", "\\*").replace("[", "\\[").replace("]", "\\]").replace("(", "\\(").replace(")", "\\)").replace("~", "\\~").replace("`", "\\`").replace(">", "\\>").replace("#", "\\#").replace("+", "\\+").replace("-", "\\-").replace("=", "\\=").replace("|", "\\|").replace("{", "\\{").replace("}", "\\}").replace(".", "\\.")

# Check if the user is an operator or group owner
async def is_authorized(update: Update):
    global operator, all_users_allowed
    user_id = update.effective_user.id
    chat_member = await update.effective_chat.get_member(user_id)

    if chat_member.status == ChatMember.OWNER or user_id == operator or all_users_allowed:
        return True
    else:
        await update.message.reply_text("你没有权限使用此命令。")
        return False

# Command handler for text messages
async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    global operator, rate, fixed_rate, usd_rate, total_in, withdrawals, transactions, recent_transactions, all_users_allowed

    text = update.message.text.strip()
    logger.info(f"Received command: {text}")

    # 权限检查
    if not await is_authorized(update):
        return

    # Handle commands
    if text == "显示账单":
        await display_combined_summary(update)

    elif text == "开始记账":
        transactions.clear()  # Clear previous transactions
        recent_transactions.clear()  # Clear recent transactions
        await update.message.reply_text("记账功能已启动")
        logger.info("Accounting started")
        return

    elif text.startswith("设置操作人"):
        if "@" in text:
            operator_username = text.split("@")[1].strip()
            user = await context.bot.get_chat_member(update.effective_chat.id, operator_username)
            operator = user.user.id
            await update.message.reply_text(f"操作人设置为 @{operator_username}")
            logger.info(f"Operator set to @{operator_username}")
        else:
            await update.message.reply_text("请提供有效的操作人，例如：设置操作人 @username")
        return

    elif text.startswith("删除操作人"):
        operator = None
        await update.message.reply_text("操作人已删除")
        return

    elif text == "设置所有人":
        all_users_allowed = True
        await update.message.reply_text("所有人现在可以使用机器人")
        return

    elif text == "显示操作人":
        if operator:
            await update.message.reply_text(f"当前操作人：@{operator}")
        else:
            await update.message.reply_text("没有设置操作人")
        return

    elif text.startswith("设置费率"):
        try:
            rate = float(text.split("设置费率")[1].strip("%"))
            await update.message.reply_text(f"费率设置为 {rate}\\%")
            logger.info(f"Rate set to {rate}%")
        except (IndexError, ValueError):
            await update.message.reply_text("请提供有效的费率，例如：设置费率 10%")
        return

    elif text.startswith("设置汇率"):
        try:
            fixed_rate = float(text.split("设置汇率")[1])
            await update.message.reply_text(f"固定汇率设置为 {fixed_rate}")
            logger.info(f"Fixed rate set to {fixed_rate}")
        except (IndexError, ValueError):
            await update.message.reply_text("请提供有效的汇率")
        return

    elif text.startswith("设置美元汇率"):
        try:
            usd_rate = float(text.split("设置美元汇率")[1])
            await update.message.reply_text(f"美元汇率设置为 {usd_rate}")
            logger.info(f"USD rate set to {usd_rate}")
        except (IndexError, ValueError):
            await update.message.reply_text("请提供有效的美元汇率")
        return

    # Deposit handling
    if "入款" in text:
        try:
            amount = float(re.findall(r'\d+', text)[0])
            total_in += amount
            transactions.append(amount)
            recent_transactions.append((amount, update.message.date.strftime('%H:%M:%S')))
            if len(recent_transactions) > 3:
                recent_transactions.pop(0)  # Keep only the latest 3 transactions
            await update.message.reply_text(f"已入款：{amount} 已记录")
            logger.info(f"Deposit recorded: {amount}")
            await display_combined_summary(update)
        except (IndexError, ValueError):
            await update.message.reply_text("请提供有效的入款金额，例如：入款 100")
        return

    # Withdrawal handling
    if "下发" in text:
        try:
            amount = float(re.findall(r'\d+', text)[0])
            total_in -= amount
            withdrawals += 1  # Increment the count of withdrawals
            await update.message.reply_text(f"已下发：{amount} 已记录")
            logger.info(f"Withdrawal recorded: {amount}")
            await display_combined_summary(update)
        except (IndexError, ValueError):
            await update.message.reply_text("请提供有效的下发金额，例如：下发 50")
        return

    # Save transactions
    if text == "保存账单":
        await update.message.reply_text("账单已保存")
        logger.info("Bill saved")
        return

    # Delete transactions
    if text == "删除账单":
        transactions.clear()  # Clear previous transactions
        await update.message.reply_text("账单已删除")
        logger.info("Bill deleted")
        return

    # If the command is not recognized
    await update.message.reply_text("命令未识别，请使用可用命令。")

# Combine today's summary and full summary in one message
async def display_combined_summary(update: Update):
    global total_in, withdrawals

    total_out = total_in - sum(transactions)  # Calculate the total withdrawn

    response = (
        f"✨ *今日账单* ✨\n\n"
        f"已入款（{len(transactions)}笔）：\n"
        f"总入款金额：{total_in:.2f}\n"
        f"费率：{rate}\\%\n"
        f"固定汇率：{fixed_rate:.2f}\n"
        f"应下发：{total_in:.2f} | {total_in / fixed_rate:.2f} (USDT)\n"
        f"已下发：{total_out:.2f} | {total_out / fixed_rate:.2f} (USDT)\n"
        f"未下发：{total_in - total_out:.2f} | {(total_in - total_out) / fixed_rate:.2f} (USDT)\n\n"
        f"最近3条入款记录：\n"
    )
    
    # Append recent transactions to the response
    for amount, time in recent_transactions:
        response += f"{time} 入款：{amount}\n"

    await update.message.reply_text(escape_markdown(response), parse_mode='MarkdownV2')
    logger.info("Combined summary displayed")


    

# Main function to start the bot
async def main():
    app = Application.builder().token(TOKEN).build()
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))

    logger.info("Bot is running")
    await app.run_polling()

if __name__ == '__main__':
    try:
        asyncio.run(main())
    except RuntimeError:
        asyncio.get_running_loop().run_until_complete(main())
