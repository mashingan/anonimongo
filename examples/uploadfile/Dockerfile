FROM nimlang/nim:alpine as build
COPY . /
RUN nim js -d:danger appjs.nim && mv appjs.js /public/js/
RUN nimble build -Y

FROM alpine
COPY --from=build /app /
COPY --from=build /public /public/
ENTRYPOINT [ "/app" ]
