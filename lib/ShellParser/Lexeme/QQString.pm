package ShellParser::Lexeme::QQString;

use strict;
use warnings;

use base 'ShellParser::Lexeme::Word';

sub as_string {
    my ($self) = @_;
    return '"' . $self->SUPER::as_string() . '"';
}

sub dequote {
    my ($self) = @_;
    $self->SUPER::as_string();
}

sub raw_string {
    my ($self) = @_;
    return '"' . $self->SUPER::raw_string() . '"';
}

1;
