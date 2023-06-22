FROM node:alpine

WORKDIR /usr/src/app

COPY pakage*.json ./
RUN npm install && npm cache clean --force

COPY . .

EXPOSE 8080
CMD [ "node", "app.js"] 
