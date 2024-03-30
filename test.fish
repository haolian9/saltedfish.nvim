

test -f $file
test -n $str
test $str = $str2
test str = str2
test ! one -gt 0.1
test one -gt 1

function foo
    :
end

set -g $fish_bind_mode abc
set -g fish_bind_mode abc
set -g 'fish_bind_mode' abc
set 'fish_bind_mode' abc
if set -x 'fish_bind_mode' abc
    :
end
