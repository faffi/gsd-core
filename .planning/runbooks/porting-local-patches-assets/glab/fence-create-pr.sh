# BSD/macOS mktemp only randomizes XXXXXX when it is the final path component, so make a
# suffixless temp then append the extension — portable across BSD + GNU (#1520).
PR_BODY_FILE=$(mktemp "${TMPDIR:-/tmp}/gsd-pr-body-XXXXXX") && mv "$PR_BODY_FILE" "${PR_BODY_FILE}.md" && PR_BODY_FILE="${PR_BODY_FILE}.md" || exit 1
trap 'rm -f "${PR_BODY_FILE:-}"' EXIT
printf '%s\n' "${PR_BODY}" > "${PR_BODY_FILE}"

if [ "$FORGE" = gitlab ]; then
  # glab has NO --body-file. Read the temp file into --description.
  # Do NOT pass `-d -`: that opens an editor and hangs a non-interactive run.
  # --template is mutually exclusive with --description; never emit both.
  glab mr create \
    --title "Phase ${PHASE_NUMBER}: ${PHASE_NAME}" \
    --description "$(cat "${PR_BODY_FILE}")" \
    --source-branch "${CURRENT_BRANCH}" \
    --target-branch "${BASE_BRANCH}" \
    --yes
else
  gh pr create \
    --title "Phase ${PHASE_NUMBER}: ${PHASE_NAME}" \
    --body-file "${PR_BODY_FILE}" \
    --base "${BASE_BRANCH}"
fi
