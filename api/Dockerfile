FROM node:22-alpine AS build
WORKDIR /app
COPY api/package*.json ./api/
RUN cd api && npm ci
COPY api/tsconfig.json ./api/
COPY api/src ./api/src
COPY database/schema.sql ./database/schema.sql
RUN cd api && npm run build

FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /app/api/package*.json ./api/
COPY --from=build /app/api/node_modules ./api/node_modules
COPY --from=build /app/api/dist ./api/dist
COPY --from=build /app/database ./database
WORKDIR /app/api
EXPOSE 3000
CMD ["node", "dist/src/index.js"]
