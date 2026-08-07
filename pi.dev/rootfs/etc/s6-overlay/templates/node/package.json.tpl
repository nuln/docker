{
  "name": "{{ PROJECT }}",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "devDependencies": {
    "tsx": "^4.19.0",
    "typescript": "^5.5.0",
    "@types/node": "^22.0.0"
  }
}