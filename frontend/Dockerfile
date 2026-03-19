FROM node:alpine
WORKDIR '/frontend'
COPY package.json ./
COPY package-lock.json ./
COPY ./ ./
RUN yarn
CMD ["yarn", "start"]