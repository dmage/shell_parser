if cat <<EOF1; cat <<EOF2; then
foo
EOF1
bar
EOF2
    echo OK;
fi
