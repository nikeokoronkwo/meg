FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY . .

RUN dart pub get --offline
RUN dart compile exe bin/meg.dart -o bin/meg


FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/meg /app/bin/

# Start server.
EXPOSE 8080
CMD ["/app/bin/meg"]