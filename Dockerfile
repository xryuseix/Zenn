FROM node:22-alpine@sha256:d1717d4b17d82f190d4dd52d3d8f02912eefb60ee703f196623fb35bba7b4991

WORKDIR /app

COPY package.json yarn.lock ./
RUN yarn install

COPY . .

ENTRYPOINT ["yarn"]
