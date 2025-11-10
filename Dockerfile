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

ENV S3_REGION="us-east1"
ENV S3_ACCESS_KEY=""
ENV S3_SECRET_KEY=""
ENV S3_URL=""
ENV S3_BUCKET=""
ENV MEG_PORT=8080

# Start server.
EXPOSE 8080
CMD ["/app/bin/meg"]