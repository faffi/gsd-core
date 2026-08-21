   FORGE_HOST=$(git remote get-url origin 2>/dev/null \
     | sed -E 's#^git@([^:]+):.*#\1#; s#^ssh://git@([^/]+)/.*#\1#; s#^https?://([^/]+)/.*#\1#')
   FORGE=""
   gh   auth status --hostname "$FORGE_HOST" >/dev/null 2>&1 && FORGE=github
   glab auth status --hostname "$FORGE_HOST" >/dev/null 2>&1 && FORGE=gitlab
   echo "forge=${FORGE:-none} host=${FORGE_HOST:-none}"
