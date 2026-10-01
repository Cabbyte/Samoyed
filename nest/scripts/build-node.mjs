import { build } from 'esbuild';
import { mkdir,cp,rm } from 'node:fs/promises';
await rm('dist-node',{recursive:true,force:true});await mkdir('dist-node/web',{recursive:true});
await build({entryPoints:['src/node.ts','src/admin.ts','src/app.ts','src/auth.ts','src/auth-storage.ts','src/self-hosted.ts','src/contracts.ts','src/domain.ts','src/storage/database.ts','src/storage/repository.ts','src/storage/sqlite.ts'],outdir:'dist-node/src',outbase:'src',bundle:false,format:'esm',platform:'node',target:'node24'});
await build({entryPoints:['web/auth.ts'],outfile:'dist-node/web/auth.js',bundle:true,format:'esm',platform:'browser',target:'es2022',minify:true});
await cp('web/index.html','dist-node/web/index.html');await cp('drizzle','dist-node/drizzle',{recursive:true});await cp('auth-migrations','dist-node/auth-migrations',{recursive:true});
