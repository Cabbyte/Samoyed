#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
exec 9>/run/lock/samoyed-nest-backup.lock
flock -w 60 9
stamp=$(TZ=Asia/Shanghai date +%Y%m%d-%H%M%S)
kind=${1:-daily}
[[ $kind == daily || $kind == release ]] || exit 2
root=/var/backups/samoyed-nest
file="$kind-$stamp.sqlite"
docker compose --project-name samoyed-nest --env-file /etc/samoyed-nest/image.env -f /opt/samoyed-nest/compose.yaml exec -T nest node dist-node/src/admin.js backup "/backups/$file" </dev/null
chmod 600 "$root/$file"
if [[ $kind == daily && $(TZ=Asia/Shanghai date +%u) == 7 ]]; then
  cp "$root/$file" "$root/weekly-$stamp.sqlite"
fi
python3 - "$root" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
for prefix, keep in [('daily', 7), ('weekly', 4)]:
    for file in sorted(root.glob(prefix + '-*.sqlite'), reverse=True)[keep:]:
        file.unlink()
PY
