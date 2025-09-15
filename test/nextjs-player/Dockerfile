# Use an official Node.js runtime as a parent image
FROM node:20-slim

# Set the working directory in the container
WORKDIR /app

# Copy package.json and package-lock.json (or yarn.lock, etc.)
COPY package*.json ./

# Install project dependencies
RUN npm install

# Copy the rest of the application source code
COPY . .

# Make port 3000 available to the world outside this container
EXPOSE 3000

# Command to run the app
CMD ["npm", "run", "dev"]
