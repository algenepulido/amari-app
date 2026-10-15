// Metro config wrapped by Sentry so an EAS build can upload source maps to
// Sentry. getSentryExpoConfig returns the standard Expo Metro config with
// Sentry's source-map handling layered on, so `expo start` and local bundling
// behave exactly as before. Source-map upload itself only runs during a build
// that has SENTRY_AUTH_TOKEN in its environment; without it, bundling is normal.
const { getSentryExpoConfig } = require('@sentry/react-native/metro');

const config = getSentryExpoConfig(__dirname);

module.exports = config;
