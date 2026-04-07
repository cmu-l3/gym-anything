FROM node:20-slim

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --only=production

COPY . .

EXPOSE 3000
CMD ["node", "index.js"]
