! fatal() {
    echo "fatal: $@" || kill -6 $$;
    exit || return&
} >&2 && echo "wtf?"&
