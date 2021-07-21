FROM nimlang/nim:alpine as build
COPY . /
RUN nimble build -Y

FROM alpine
COPY --from=build /app /
COPY public /public/
ENTRYPOINT [ "/app" ]
