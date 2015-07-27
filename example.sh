while [ 1 -gt 2 ]; do
    :
done

while
    # a couple of <newline>s


    # a list
    date && who || ls; cat file
    # a couple of <newline>s


    # another list
    wc file > output & false

do
    # 2 lists
    ls | foo | # xxx
    bar
    cat file
done

while ! cat <<END; do
Hello, world!
END
    echo Retry...
done
