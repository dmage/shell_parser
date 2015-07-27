package ShellParser::Lexeme::NewLine;

use strict;
use warnings;

use base 'ShellParser::Lexeme';

sub new {
    my ($class) = @_;
    return bless({}, $class);
}

sub as_string {
    return "\n";
}

sub raw_string {
    return "\n";
}

1;
