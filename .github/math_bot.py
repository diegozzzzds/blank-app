import logging
import pytesseract
import numpy as np
import cv2
from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, filters, CallbackContext
import sympy as sp

# Configure logging
logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)
logger = logging.getLogger(__name__)

# Function to handle text messages
async def start(update: Update, context: CallbackContext) -> None:
    await update.message.reply_text('Hello! Send me a math problem in text or an image, and I will solve it for you.')

# Function to process images
def process_image(image_path: str) -> str:
    # Load the image
    img = cv2.imread(image_path)
    # Convert the image to gray scale
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    # Use pytesseract to extract text
    text = pytesseract.image_to_string(gray)
    return text

# Function to handle incoming messages
async def handle_message(update: Update, context: CallbackContext) -> None:
    if update.message.photo:
        # Get the file ID of the photo
        photo_file = await update.message.photo[-1].get_file()  # 使用 await
        await photo_file.download('temp_image.jpg')  # 使用 await
        # Process the image to extract text
        math_problem = process_image('temp_image.jpg')
        await update.message.reply_text(f'Extracted problem: {math_problem}')
    else:
        math_problem = update.message.text
        await update.message.reply_text(f'You sent: {math_problem}')

    # Solve the math problem
    try:
        solution = sp.sympify(math_problem)
        result = solution.evalf()
        await update.message.reply_text(f'Solution: {result}')
    except Exception as e:
        await update.message.reply_text(f'Error solving the problem: {e}')

# Main function to start the bot
def main() -> None:
    # Create the Application and pass it your bot's token
    application = ApplicationBuilder().token("8012577222:AAFUpMidfwWgla34KtIKUCn34DyZYvq5q9o").build()  # 在这里替换为你的机器人令牌

    # Register command and message handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(MessageHandler(filters.TEXT | filters.PHOTO, handle_message))

    # Start the Bot
    application.run_polling()

if __name__ == '__main__':
    main()
