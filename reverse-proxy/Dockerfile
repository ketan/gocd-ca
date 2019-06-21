FROM nginx:alpine

RUN apk add -U openssl bash easypki

COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY nginx-conf /nginx-conf

ENTRYPOINT [ "/docker-entrypoint.sh" ]

