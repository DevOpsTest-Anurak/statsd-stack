# Stage 1: Build stage
FROM node:16 as build

WORKDIR /app

COPY package*.json ./

RUN npm ci

COPY . .

# Stage 2: Runtime stage
FROM node:16-alpine

WORKDIR /app

COPY --from=build /app .

CMD [ "node", "index.js" ]