# Task 1 - Image 2: Node.js metrics collector service
# Uses node:18-bullseye-slim (Debian Bullseye, working repos) with
# intentionally old npm packages that have documented CRITICAL CVEs.
# ejs==1.0.0 has CVE-2022-29078 (CRITICAL - Server-Side Template Injection)
# jsonwebtoken@8.5.1 has CVE-2022-23529 (CRITICAL - Signature bypass)
# Fix: upgrade ejs>=3.1.7, jsonwebtoken>=9.0.0 in package.json, then rebuild.
FROM node:18-bullseye-slim

WORKDIR /app

COPY package.json .
RUN npm install --production

COPY server.js .

EXPOSE 3000
CMD ["node", "server.js"]
