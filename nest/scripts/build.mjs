import { build } from 'esbuild';
import { mkdir, cp, rm } from 'node:fs/promises';
await rm('dist', { recursive: true, force: true });
await mkdir('dist/server', { recursive: true });
await build({ entryPoints: ['src/worker.ts'], outfile: 'dist/server/index.js', bundle: true, format: 'esm', platform: 'browser', target: 'es2022' });
await cp('.openai', 'dist/.openai', { recursive: true });

await cp('drizzle', 'dist/drizzle', { recursive: true });
