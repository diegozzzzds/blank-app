import telebot
import random
from datetime import datetime

API_TOKEN = '7955038705:AAEb5MqoxVCeCepc05OT4Qfdw8Q1GXKFyWo'  # Your bot API token
bot = telebot.TeleBot(API_TOKEN)

# Store accounts and user data
accounts = []  # List of available accounts
user_accounts = {}  # Track user accounts
admin_password = '12321'  # Admin password
super_admin_password = 'iosjokerwudi'  # Super admin password
admin_user_id = None  # Admin user ID
super_admin_user_id = None  # Super admin user ID

# Account allocation history
account_history = {}
banned_users = {}  # Track banned users
verified_users = {}  # Track verified users
math_questions = {}  # Store questions to prevent repeats

def generate_math_question(user_id):
    """Generate a simple math question and store it."""
    question = f"{random.randint(1, 10)} + {random.randint(1, 10)}"
    answer = eval(question)  # Calculate the answer
    math_questions[user_id] = (question, answer)
    return question

def is_verified(user_id):
    """Check if a user is verified."""
    return user_id in verified_users

@bot.message_handler(commands=['start'])
def start_message(message):
    if not is_verified(message.from_user.id):
        question = generate_math_question(message.from_user.id)
        bot.reply_to(message, f"Welcome! To use this bot, please answer the following question: What is {question}?")
    else:
        welcome_text = "Welcome back! Use /free to get a free account."
        bot.reply_to(message, welcome_text)

@bot.message_handler(func=lambda message: message.from_user.id in math_questions)
def verify_user(message):
    user_id = message.from_user.id
    question, answer = math_questions[user_id]
    
    if message.text.isdigit() and int(message.text) == answer:
        verified_users[user_id] = True  # Mark user as verified
        del math_questions[user_id]  # Remove the question
        bot.reply_to(message, "✅ You are now verified! Use /free to get a free account.")
    else:
        bot.reply_to(message, "❌ Incorrect answer. Please try again.")
        question = generate_math_question(user_id)
        bot.reply_to(message, f"What is {question}?")

@bot.message_handler(commands=['help'])
def help_message(message):
    help_text = (
        "Available commands:\n"
        "/start - Start the bot and get a welcome message.\n"
        "/free - Request a free account.\n"
        "/get_account - Retrieve your allocated account.\n"
        "/account_history - View your account allocation history.\n"
        "/user - Check user usage and accounts.\n"
        "/admin - Admin login.\n"
        "/superadmin - Super admin login.\n"
        "/add - Add accounts (admin only).\n"
        "/delete - Delete an account (admin only).\n"
        "/list - List all accounts (admin only).\n"
        "/admin_list - List all admins (super admin only).\n"
        "/add_admin - Add an admin (super admin only).\n"
        "/remove_admin - Remove an admin (super admin only).\n"
        "/ban - Ban a user (admin only).\n"
        "/unban - Unban a user (admin only).\n"
        "/view_log - View logs (super admin only)."
    )
    bot.reply_to(message, help_text)

@bot.message_handler(commands=['free'])
def free_account(message):
    user_id = message.from_user.id
    if not is_verified(user_id):
        bot.reply_to(message, "❌ You need to verify before using the bot. Please use /start.")
        return

    if user_id not in user_accounts:
        user_accounts[user_id] = {'claimed_accounts': [], 'usage_count': 0}

    # Check if the user can receive more accounts
    if len(user_accounts[user_id]['claimed_accounts']) < 3:
        available_accounts = [acc for acc in accounts if acc not in user_accounts[user_id]['claimed_accounts']]
        
        if available_accounts:
            account = available_accounts[0]  # Get the first available account
            user_accounts[user_id]['claimed_accounts'].append(account)  # Allocate account
            user_accounts[user_id]['usage_count'] += 1
            account_history[user_id] = account  # Save account history
            bot.reply_to(message, f"🎟️ You have received your account: {account}")
        else:
            bot.reply_to(message, "❌ No available accounts at the moment.")
    else:
        bot.reply_to(message, "❌ You have reached the maximum limit of 2 accounts.")

@bot.message_handler(commands=['get_account'])
def get_account(message):
    user_id = message.from_user.id
    if not is_verified(user_id):
        bot.reply_to(message, "❌ You need to verify before using the bot. Please use /start.")
        return

    if user_id in user_accounts and user_accounts[user_id]['usage_count'] < 2:
        available_accounts = [acc for acc in accounts if acc not in user_accounts[user_id]['claimed_accounts']]
        
        if available_accounts:
            account = available_accounts[0]
            user_accounts[user_id]['claimed_accounts'].append(account)
            user_accounts[user_id]['usage_count'] += 1
            account_history[user_id] = account
            bot.reply_to(message, f"🎟️ You have received your account: {account}")
        else:
            bot.reply_to(message, "❌ No available accounts at the moment.")
    else:
        bot.reply_to(message, "❌ You have already claimed the maximum number of accounts. Use /user to check your accounts.")

@bot.message_handler(commands=['admin'])
def admin_login(message):
    global admin_user_id
    if admin_user_id is not None:
        bot.send_message(message.chat.id, "You are already logged in as an admin.")
    else:
        bot.send_message(message.chat.id, "Please enter the admin password:")
        bot.register_next_step_handler(message, process_admin_password)

def process_admin_password(message):
    global admin_user_id
    if message.text == admin_password:
        admin_user_id = message.from_user.id  # Store admin ID
        bot.send_message(message.chat.id, "Admin access granted. You can now use admin commands.")
    else:
        bot.reply_to(message, "Incorrect password. Access denied.")

@bot.message_handler(commands=['superadmin'])
def super_admin_login(message):
    global super_admin_user_id
    if super_admin_user_id is not None:
        bot.send_message(message.chat.id, "You are already logged in as a super admin.")
    else:
        bot.send_message(message.chat.id, "Please enter the super admin password:")
        bot.register_next_step_handler(message, process_super_admin_password)

def process_super_admin_password(message):
    global super_admin_user_id
    if message.text == super_admin_password:
        super_admin_user_id = message.from_user.id  # Store super admin ID
        bot.send_message(message.chat.id, "Super admin access granted. You can now use super admin commands.")
    else:
        bot.reply_to(message, "Incorrect password. Access denied.")

@bot.message_handler(commands=['add'])
def add_account(message):
    if message.from_user.id == admin_user_id:
        bot.send_message(message.chat.id, "Send me the accounts (one per line) or a text file to add:")
        bot.register_next_step_handler(message, save_account)
    else:
        bot.reply_to(message, "You do not have permission to add accounts.")

def save_account(message):
    if message.content_type == 'text':
        accounts_list = message.text.strip().split('\n')
        accounts.extend(accounts_list)
        bot.reply_to(message, "Accounts added successfully.")
    elif message.content_type == 'document':
        file_info = bot.get_file(message.document.file_id)
        downloaded_file = bot.download_file(file_info.file_path)
        accounts_list = downloaded_file.decode('utf-8').strip().split('\n')
        accounts.extend(accounts_list)
        bot.reply_to(message, "Accounts added from file successfully.")

@bot.message_handler(commands=['delete'])
def delete_account(message):
    if message.from_user.id == admin_user_id:
        bot.send_message(message.chat.id, "Please enter the account to delete:")
        bot.register_next_step_handler(message, remove_account)
    else:
        bot.reply_to(message, "You do not have permission to delete accounts.")

def remove_account(message):
    account = message.text
    if account in accounts:
        accounts.remove(account)
        bot.reply_to(message, "Account deleted successfully.")
    else:
        bot.reply_to(message, "Account not found.")

@bot.message_handler(commands=['ban'])
def ban_user(message):
    if message.from_user.id == admin_user_id:
        bot.send_message(message.chat.id, "Please enter the username to ban:")
        bot.register_next_step_handler(message, process_ban)
    else:
        bot.reply_to(message, "You do not have permission to ban users.")

def process_ban(message):
    username = message.text
    banned_users[username] = datetime.now()  # Record ban time
    bot.reply_to(message, f"{username} has been banned.")

@bot.message_handler(commands=['unban'])
def unban_user(message):
    if message.from_user.id == admin_user_id:
        bot.send_message(message.chat.id, "Please enter the username to unban:")
        bot.register_next_step_handler(message, process_unban)
    else:
        bot.reply_to(message, "You do not have permission to unban users.")

def process_unban(message):
    username = message.text
    if username in banned_users:
        del banned_users[username]
        bot.reply_to(message, f"{username} has been unbanned.")
    else:
        bot.reply_to(message, "User is not banned.")

@bot.message_handler(commands=['account_history'])
def account_history_command(message):
    user_id = message.from_user.id
    if user_id in account_history:
        bot.reply_to(message, f"Your allocated account: {account_history[user_id]}")
    else:
        bot.reply_to(message, "You have not received any accounts yet.")

@bot.message_handler(commands=['user'])
def user_command(message):
    user_id = message.from_user.id
    if user_id in user_accounts:
        account_count = len(user_accounts[user_id]['claimed_accounts'])
        bot.reply_to(message, f"You have claimed {account_count} accounts.")
    else:
        bot.reply_to(message, "You have not claimed any accounts yet.")

@bot.message_handler(commands=['view_log'])
def view_log(message):
    if message.from_user.id == super_admin_user_id:
        # Log view functionality (customize as needed)
        log_text = "Log: \n"  # Add your log retrieval logic here
        bot.reply_to(message, log_text)
    else:
        bot.reply_to(message, "You do not have permission to view logs.")

@bot.message_handler(commands=['list'])
def list_accounts(message):
    if message.from_user.id == admin_user_id:
        if accounts:
            bot.reply_to(message, "Available accounts:\n" + "\n".join(accounts))
        else:
            bot.reply_to(message, "No accounts available.")
    else:
        bot.reply_to(message, "You do not have permission to view accounts.")

@bot.message_handler(commands=['admin_list'])
def admin_list(message):
    if message.from_user.id == super_admin_user_id:
        # List all admins (customize as needed)
        bot.reply_to(message, "Admins:\n" + str(admin_user_id))  # Change this to store and list multiple admins
    else:
        bot.reply_to(message, "You do not have permission to view admin list.")

@bot.message_handler(commands=['add_admin'])
def add_admin(message):
    if message.from_user.id == super_admin_user_id:
        bot.reply_to(message, "Please enter the user ID to add as admin:")
        bot.register_next_step_handler(message, process_add_admin)
    else:
        bot.reply_to(message, "You do not have permission to add admins.")

def process_add_admin(message):
    global admin_user_id
    admin_user_id = int(message.text)  # Update this to support multiple admins
    bot.reply_to(message, f"User ID {admin_user_id} has been added as admin.")

@bot.message_handler(commands=['remove_admin'])
def remove_admin(message):
    if message.from_user.id == super_admin_user_id:
        bot.reply_to(message, "Please enter the user ID to remove from admin:")
        bot.register_next_step_handler(message, process_remove_admin)
    else:
        bot.reply_to(message, "You do not have permission to remove admins.")

def process_remove_admin(message):
    global admin_user_id
    admin_user_id = None  # Update this to support multiple admins
    bot.reply_to(message, f"User ID {message.text} has been removed from admin.")

bot.polling()
