#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;
use List::Util qw{first};

#####################################################################
#
#	Script by hguilla
#
#	Este script es ofrecido gratis y de buena voluntad
#	No se ofrece ninguna garantia o soporte sobre su funcionamiento
#
#####################################################################

my $input_filename = $ARGV[0];
if ($input_filename eq '--help' || $input_filename eq '-h') {
	uso();
	exit(0);
}

my $input_fh;
if (! open $input_fh, '<', "$input_filename") {
	die "Error al abrir el archivo para lectura: $!";
}

my $REGISTROS_A_PRESERVAR = {
	RBX => 1,
	R12 => 1,
	R13 => 1,
	R14 => 1,
	R15 => 1,
};

sub registros_64 {
	my ($r) = @_;

	my $r64s = {
		AL   => 'RAX',
		AX   => 'RAX',
		EAX  => 'RAX',
		RAX  => 'RAX',
		BL   => 'RBX',
		BX   => 'RBX',
		EBX  => 'RBX',
		RBX  => 'RBX',
		CL   => 'RCX',
		CX   => 'RCX',
		ECX  => 'RCX',
		RCX  => 'RCX',
		DL   => 'RDX',
		DX   => 'RDX',
		EDX  => 'RDX',
		RDX  => 'RDX',
		DL   => 'RDI',
		DIL  => 'RDI',
		EDI  => 'RDI',
		RDI  => 'RDI',
		SIL  => 'RSI',
		SI   => 'RSI',
		ESI  => 'RSI',
		RSI  => 'RSI',
		BPI  => 'RBP',
		BP   => 'RBP',
		EBP  => 'RBP',
		RBP  => 'RBP',
		SPL  => 'RSP',
		SP   => 'RSP',
		ESP  => 'RSP',
		RSP  => 'RSP',
		R8B  => 'R8',
		R8W  => 'R8',
		R8D  => 'R8',
		R8   => 'R8',
		R9B  => 'R9',
		R9W  => 'R9',
		R9D  => 'R9',
		R9   => 'R9',
		R10B => 'R10',
		R10W => 'R10',
		R10D => 'R10',
		R10  => 'R10',
		R11B => 'R11',
		R11W => 'R11',
		R11D => 'R11',
		R11  => 'R11',
		R12B => 'R12',
		R12W => 'R12',
		R12D => 'R12',
		R12  => 'R12',
		R13B => 'R13',
		R13W => 'R13',
		R13D => 'R13',
		R13  => 'R13',
		R14B => 'R14',
		R14W => 'R14',
		R14D => 'R14',
		R14  => 'R14',
		R15B => 'R15',
		R15W => 'R15',
		R15D => 'R15',
		R15  => 'R15',
	};
	return $r64s->{$r};
}

my $pila = 0;
my $function;
my $errores = 0;
my $registros_preservados = [];
my $registros_que_se_pushaeron = {};
my $registros_que_se_usaron = {};

my $line;
my $line_num = 0;
while ($line = <$input_fh>) {
	chomp $line;

	$line_num++;
	if ($line =~ m{^[\s]*[;]}xms) {
		# Es comentario
		next;
	}
	if (! $function) {
		if ($line =~ m{\s*(\w+)[:]}) {
			$function = $1;
		}
		next;
	}

	if ($line =~ m{^[\s]*PUSH[\s]*([\w]+)}xmsi) {
		$pila += 8;
		my $registro = $1;
		if (! pushear($registros_preservados, $registro)) {
			$errores++;
			warn "El error fue en la linea $line_num";
		}
	} elsif ($line =~ m{^[\s]*SUB[\s]*RSP[\s]*[,][\s]*(\d+)}xmsi) {
		my $bytes = $1;
		$pila += $bytes;
		if (! pushear($registros_preservados, $bytes)) {
			$errores++;
			warn "El error fue en la linea $line_num";
		}
	} elsif ($line =~ m{^[\s]*POP[\s]*([\w]+)}xms) {
		$pila -= 8;
		my $registro = $1;
		if (! popear($registros_preservados, $registro)) {
			$errores++;
			warn "El error fue en la linea $line_num";
		}
	} elsif ($line =~ m{^[\s]*ADD[\s]*RSP[\s]*[,][\s]*(\d+)}xmsi) {
		my $bytes = $1;
		$pila -= $bytes;
		if (! popear($registros_preservados, $bytes)) {
			$errores++;
			warn "El error fue en la linea $line_num";
		}
	} elsif ($line =~ m{^[\s]+(?:(?:MOV)|(?:INC)|(?:ADD)|(?:SUB)|(?:LEA))[\s]+(.+?)$}xmsi) {
		my $r = $1;
		if ($r =~ m{(?:(?:byte)|(?:word)|(?:dword)|(?:qword))[\s]*([\w]+)[\s]*,}xmsi) {
			$r = $1;
		} elsif ($r =~ m{(\w+),}xmsi) {
			$r = $1;
		} else {
			next;
		}
		my $r64 = registros_64(uc($r));
		if ($REGISTROS_A_PRESERVAR->{$r64} && ! registro_ya_esta_pusheado($registros_preservados, $r64)) {
			$errores++;
			warn "Error: El registro $r se usa en la funcion $function"
				. " pero $r64 nunca fue pusheado. Esto rompe la convencion C";
		}
		$registros_que_se_usaron->{$r64} = 1;
	} elsif ($line =~ m{^[\s]+CALL}xmsi) {
		if ($pila % 16 != 0) {
			$errores++;
			warn "Error: Se hace un CALL con la pila desalineada en la funcion $function";
		}
	} elsif ($line =~ m{^[\s]*RET}xmsi) {
		if ($pila > 8) {
			$errores++;
			warn "Error: Faltan hacer POPs en la funcion $function";
		} elsif ($pila < 8) {
			$errores++;
			warn "Se POPeo de mas o se pusheo de menos en la funcion $function";
		}
		foreach my $r64 (keys %$registros_que_se_pushaeron) {
			if (! $registros_que_se_usaron->{$r64}) {
				$errores++;
				warn "Error: El registro $r64 se pusheo en la funcion $function pero no se uso";
			}
		}

		if (!$errores) {
			print "Se verifico correctamente la funcion $function y no se encontraron errores\n";
		} else {
			warn "Se encontraron $errores errores en la funcion $function";
		}
		$registros_preservados = [];
		$registros_que_se_pushaeron = {};
		$registros_que_se_usaron = {};
		$pila = 8;
		$function = undef();
		$errores = 0;
	}
}

close($input_fh);

sub pushear {
	my ($pila_registros, $registro) = @_;
	if (registro_ya_esta_pusheado($pila_registros, $registro)) {
		warn "Error: El registro ya estaba pusheado";
	}
	if (es_numero($registro) && scalar @$pila_registros) {
		my $ultimo_agregado = pop @$pila_registros;
		if (es_numero($ultimo_agregado)) {
			push(@$pila_registros, $registro + $ultimo_agregado);
		} else {
			push(@$pila_registros, $ultimo_agregado);
			push(@$pila_registros, $registro);
		}
	} else {
		push(@$pila_registros, $registro);
	}
	return 1;
}

sub popear {
	my ($pila_registros, $registro) = @_;
	if (! @$pila_registros) {
		warn "Error: La pila esta vacia y se le esta haciendo POP";
		return undef();
	}

	my $pop = pop(@$pila_registros);
	if (es_numero($registro)) {
		if (es_numero($pop)) {
			my $resta = $pop - $registro;
			if ($resta > 0) {
				push(@$pila_registros, $resta);
			} elsif ($resta < 0) {
				warn "Error: Sumaste más de lo que habias restado a la pila";
				return undef();
			}
			return 1;
		} else {
			warn "Error: Estas sumando a la pila y te olvidaste de hacer POP al registro $pop";
			return undef();
		}
	} elsif (es_numero($pop)) {
		warn "Error: Estas haciendo POP y lo ultimo que tenes en la pila no pertenecia a ningun registro";
		return undef();
	}
	if (uc($pop) ne uc($registro)) {
		warn "Error: Se esta intentando POPear en el registro $registro pero en la pila estaba guardado el registro $pop";
		return undef();
	}
	return 1;
}

sub registro_ya_esta_pusheado {
	my ($pila_registros, $registro) = @_;
	return scalar(grep { uc($_) eq uc($registro) } @$pila_registros);
}

sub es_numero {
	my ($valor) = @_;
	if ($valor =~ m{^[\d]$}xms) {
		return 1;
	}
	return 0;
}

sub uso {
	print << "END_USO";
$0 <file>

Analiza el archivo <file> por posibles errores de alineacion en la pila.
END_USO
}

exit(0);
