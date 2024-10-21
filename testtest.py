import os
import re
import asyncio
from telethon import TelegramClient
from telethon.tl.types import InputPeerChannel

# Replace these with your own values
api_id = 'YOUR_API_ID'
api_hash = 'YOUR_API_HASH'
channel_username = 'CHANNEL_USERNAME'  # e.g., 'username' or 'channel_id'
message_id = 558  # The message ID from the link

# Create a directory to save videos
if not os.path.exists('videos'):
    os.makedirs('videos')

async def main():
    async with TelegramClient('session_name', api_id, api_hash) as client:
        # Get the channel
        channel = await client.get_entity(channel_username)
        
        # Get the message
        message = await client.get_message(channel, message_id)
        
        # Check if the message contains a video
        if message.video:
            # Download the video
            await client.download_media(message.video, f'videos/{message.video.file.name}')
            print(f'Downloaded: {message.video.file.name}')
        else:
            print('No video found in the specified message.')

if __name__ == '__main__':
    asyncio.run(main())