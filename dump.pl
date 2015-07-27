#!/usr/bin/env perl

use strict;
use warnings;

package Error;

use overload '""' => sub { $_[0]->as_string() };

sub new {
	my ($class, $msg) = @_;
	return bless({
		msg => $msg,
	}, $class);
}

sub as_string {
	my ($self) = @_;
	return $self->{msg};
}

package LexemeBuffer;

sub new {
	my ($class, $check) = @_;
	return bless({
		buf => [],
		check => $check // sub { return },
		err => undef,
	}, $class);
}

sub print {
	my ($self, $lexeme) = @_;

	return if defined($self->{err});

	my $err = $self->{check}->($lexeme);
	if (defined($err)) {
		$self->{err} = $err;
		return;
	}

	push(@{$self->{buf}}, $lexeme);
}

sub copy_to {
	my ($self, $writer) = @_;
	foreach my $x (@{$self->{buf}}) {
		$writer->print($x);
	}
}

sub err {
	my ($self) = @_;
	return $self->{err};
}

package LexemeWriter;

sub new {
	my ($class) = @_;
	return bless({
		heredoc_buf => [],
	}, $class);
}

sub flush {
	my ($self) = @_;
	while (my $heredoc = shift(@{$self->{heredoc_buf}})) {
		foreach my $line (@{$heredoc->{lines}}) {
			print $line->raw_string() . "\n";
		}
		print $heredoc->{here_end}->dequote() . "\n";
	}
}

sub print {
	my ($self, $lexeme) = @_;
	if ($lexeme->isa("ShellParser::Lexeme::HereDoc")) {
		push(@{$self->{heredoc_buf}}, $lexeme);
	}
	print $lexeme->as_string();
	if ($lexeme->isa("ShellParser::Lexeme::NewLine")) {
		$self->flush();
	}
}

sub err {
	return;
}

package main;

use ShellParser;
use ShellParser::Lexeme::NewLine;
use Carp qw(cluck);

# my $INDENT = "‹ T A B ›";
my $INDENT = "⇢\t";

sub dump_token {
	my ($writer, $compactness, $prefix, $token) = @_;

	# $prefix = "\n" . $prefix . "[" . $token . "]";
	# print "[$prefix] " . $token . "\n";

	if ($token->isa("ShellParser::Lexeme")) {
		$writer->print($token);
		return $writer->err();
	}

	if (ref($token) eq "ShellParser::Token::List") {
		foreach my $i (0..$#{$token->{body}}) {
			if (ref($token->{body}->[$i]) eq "ShellParser::Token::Comments") {
				if (@{$token->{body}->[$i]->{body}} > 0 && $compactness == 1) {
					$writer->print(ShellParser::Lexeme->new($prefix));
				}
			} elsif (ref($token->{body}->[$i]) eq "ShellParser::Token::AndOrList") {
				if ($compactness == 1) {
					$writer->print(ShellParser::Lexeme->new($prefix));
				}
			} else {
				return Error->new("unexpected token $token->{body}->[$i] inside of $token");
			}
			my $err = dump_token($writer, $compactness, $prefix, $token->{body}->[$i]);
			return $err if defined($err);
		}
		return $writer->err();
	}

	if (ref($token) eq "ShellParser::Token::Comments") {
		foreach my $i (0..$#{$token->{body}}) {
			if ($compactness == 1 && $i > 0) {
				$writer->print(ShellParser::Lexeme->new($prefix . $INDENT));
			}
			$writer->print($token->{body}->[$i]);
			$writer->print(ShellParser::Lexeme::NewLine->new());
		}
		return $writer->err();
	}

	if (ref($token) eq "ShellParser::Token::AndOrList") {
		foreach my $elem (@{$token->{body}}) {
			if ($elem->isa("ShellParser::Lexeme::Operator")) {
				$writer->print(ShellParser::Lexeme->new(" "));
				$writer->print($elem);
				$writer->print(ShellParser::Lexeme->new(" "));
			} else {
				if (ref($elem) eq "ShellParser::Token::Comments" && @{$elem->{body}}) {
					$writer->print(ShellParser::Lexeme->new(" "));
				}
				my $err = dump_token($writer, $compactness, $prefix, $elem);
				return $err if defined($err);
			}
		}
		if ($compactness >= 2) {
			$writer->print(ShellParser::Lexeme->new(";"));
		} else {
			$writer->print(ShellParser::Lexeme::NewLine->new());
		}
		return $writer->err();
	}

	if (ref($token) eq "ShellParser::Token::Pipeline") {
		if ($token->{banged}) {
			$writer->print(ShellParser::Lexeme->new("! "));
		}
		foreach my $i (0..$#{$token->{body}}) {
			my $err = dump_token($writer, $compactness, $prefix, $token->{body}->[$i]);
			return $err if defined($err);

			my $wanna_pipe = 0;
			for (my $j = $i + 1; $j <= $#{$token->{body}}; $j++) {
				if (ref($token->{body}->[$j]) eq "ShellParser::Token::SimpleCommand") {
					$wanna_pipe = 1;
					last;
				}
			}

			if (ref($token->{body}->[$i]) eq "ShellParser::Token::SimpleCommand" ||
				ref($token->{body}->[$i]) eq "ShellParser::Token::CompoundCommand") {
				if ($wanna_pipe) {
					$writer->print(ShellParser::Lexeme->new(" | "));
				}
			} elsif (ref($token->{body}->[$i]) eq "ShellParser::Token::Comments") {
				if (@{$token->{body}->[$i]->{body}} > 0 && $wanna_pipe) {
					$writer->print(ShellParser::Lexeme->new($prefix . $INDENT));
				}
			} else {
				return Error->new("unexpected token $token->{body}->[$i] inside of $token");
			}
		}
		return $writer->err();
	}

	if (ref($token) eq "ShellParser::Token::CompoundCommand") {
		my $err = dump_token($writer, $compactness, $prefix, $token->{body});
		return $err if defined($err);
		# TODO(dmage): $token->{redirect}
		return $writer->err();
	}

	if (ref($token) eq "ShellParser::Token::While") {
		$writer->print(ShellParser::Lexeme->new("while"));

		my $buf;
		if ($compactness < 2) {
			$buf = LexemeBuffer->new(sub {
				my ($lexeme) = @_;
				if ($lexeme->isa("ShellParser::Lexeme::Comment") ||
					$lexeme->isa("ShellParser::Lexeme::NewLine")) {
					return Error->new("forbidden in this mode");
				}
				return;
			});
			my $err = dump_token($buf, 2, $prefix . $INDENT, $token->{condition});
			if (!defined($err)) {
				$writer->print(ShellParser::Lexeme->new(" "));
				$buf->copy_to($writer);
				$writer->print(ShellParser::Lexeme->new(" do"));
				$writer->print(ShellParser::Lexeme::NewLine->new());
			} else {
				$buf = LexemeBuffer->new();
				$err = dump_token($buf, $compactness, $prefix . $INDENT, $token->{condition});
				return $err if defined($err);

				$writer->print(ShellParser::Lexeme::NewLine->new());
				$buf->copy_to($writer);
				$writer->print(ShellParser::Lexeme->new("do"));
				$writer->print(ShellParser::Lexeme::NewLine->new());
			}
		} else {
			$buf = LexemeBuffer->new();
			my $err = dump_token($buf, $compactness, $prefix . $INDENT, $token->{condition});
			return $err if defined($err);

			$writer->print(ShellParser::Lexeme->new(" "));
			$buf->copy_to($writer);
			$writer->print(ShellParser::Lexeme->new(" do"));
			$writer->print(ShellParser::Lexeme::NewLine->new());
		}

		my $err = dump_token($writer, $compactness, $prefix . $INDENT, $token->{body});
		return $err if defined($err);

		$writer->print(ShellParser::Lexeme->new("done"));
		return $writer->err();
	}

	if (ref($token) eq "ShellParser::Token::SimpleCommand") {
		# TODO(dmage): $token->{prefix}
		my $err = dump_token($writer, $compactness, $prefix . $INDENT, $token->{name});
		return $err if defined($err);
		foreach my $arg (@{$token->{args}}) {
			if (ref($arg) eq "ShellParser::Token::Redirection") {
				# TODO(dmage): redirection
				next;
			}
			$writer->print(ShellParser::Lexeme->new(" "));
			$err = dump_token($writer, $compactness, $prefix . $INDENT, $arg);
			return $err if defined($err);
		}
		return $writer->err();
	}

	use Data::Dumper;
	print Dumper($token);

	return Error->new("unexpected token $token");
}

sub parse_file {
	my ($filename) = @_;

	my $p = ShellParser->new();

	open(my $fh, '<', $filename) or die $!;

	my $lineno = 0;
	my $result = $p->parse(sub {
		$lineno++;
		return scalar <$fh>;
	});

	if (!$result) {
	    my $err = $p->error;

	    my $line = ($err->{line} // "(EOF)");
	    chomp($line);
	    $line =~ s/\t/ /;

	    my $lineno_prefix = "$lineno: ";
	    print $lineno_prefix . $line . "\n";
	    print "-" x (length($lineno_prefix) + ($err->{position} // 1) - 1) . "^\n";
	    print $err->{message} . "\n";
	    exit(1);
	}

	return $result;
}

my $result = parse_file($ARGV[0]);
my $writer = LexemeWriter->new();
my $err = dump_token($writer, 1, "", $result);
if ($err) {
	print "ERROR: $err\n";
}
