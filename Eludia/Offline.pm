use POSIX qw(setuid setgid getuid getgid);
no warnings;

################################################################################

sub offline_script_log_signature () {

	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime (time);

	$year += 1900;

	$mon ++;

	return sprintf "[%04d-%02d-%02d %02d:%02d:%02d $$ $0] ", $year, $mon, $mday, $hour, $min, $sec;

}

################################################################################

sub lock_file_name () {

	my $fn = File::Spec -> rel2abs ($0);

	$fn = readlink $fn while -l $fn;

	$fn =~ y{\\/.\: }{___};

	return $^O eq 'MSWin32' ? "C:/$fn.lock" : "$fn.lock";

}

################################################################################

sub initialize_offline_script_execution {

	my $preconf = $_[0];

	my $user = $preconf -> {user};

	my $current_uid = getuid();

	my $new_uid,$new_gid;

	if ($user && $^O ne 'MSWin32') {

		my ($pwName, $pwCode, $pwUid, $pwGid, $pwQuota, $pwComment, $pwGcos, $pwHome, $pwLogprog) = getpwnam($user);

		if ($pwUid != $current_uid && $current_uid != 0) {

			warn "Can't change uid to '$user', cos you are not root user.";
			exit;

		}

		$new_uid = $pwUid;
		$new_gid = $pwGid;

	}

	our $lock_file_dir = $^O eq 'MSWin32' ? "" : "/var/run/eludia_" . ($user ? $user : getpwuid($<)) . "/";

	$ENV {ELUDIA_SILENT} or warn "\n" . offline_script_log_signature . " starting...\n";

	eval 'require LockFile::Simple';

	if ($LockFile::Simple::VERSION && !$preconf -> {no_lock_offline_scripts}) {

		if ($^O ne 'MSWin32') {

			unless ( -d $lock_file_dir ) {

				unless ( mkdir $lock_file_dir ) {

					warn "Can't create directory $lock_file_dir. Quit.\n";

					exit;

				}

			}

			if ( $new_uid ) {

				unless (chown ($new_uid, $new_gid, $lock_file_dir)) {

					warn "Can't change owner to $lock_file_dir. Quit.\n";

					exit;

				}

				setgid ($new_gid);
				setuid ($new_uid);

			}

		}

		our $LOCK_MANAGER = LockFile::Simple -> make (

			-autoclean => 1,

			-stale => 1,

		);

		my $fn = $lock_file_dir . lock_file_name;

		unless ($LOCK_MANAGER -> trylock ($fn)) {

			warn offline_script_log_signature . "Can't acquire a lock $fn. Quit.\n";

			exit;

		}

	} else {

		if ( $new_uid ) {

			setgid ($new_gid);
			setuid ($new_uid);

		}

	}

}

################################################################################

sub finalize_offline_script_execution () {

	if ($LOCK_MANAGER) {

		$LOCK_MANAGER -> unlock ($lock_file_dir . lock_file_name);

	}

	$ENV {ELUDIA_SILENT} or warn offline_script_log_signature . " finished.\n";

}

################################################################################

sub config_file () {

	use File::Spec;

	my $fn = File::Spec -> rel2abs ($0);

	$fn = readlink $fn while -l $fn;

	$fn =~ y{\\}{/};

	$fn =~ s{/(lib|t)/.*}{/conf/httpd.conf};

	return $fn;

}

################################################################################

sub perl_section_from ($) {

	my ($fn) = @_;

	my $code = '';
	my $flag = 0;

	open (CONF, $fn) or die ("Can't open $fn:$!\n");

	while (<CONF>) {

		if (/<[Pp]erl\s*>/)      { $flag = 1   }

		elsif (/<\/[Pp]erl\s*>/) { $flag = 0   }

		elsif ($flag)            { $code .= $_ }

	}

	close (CONF);

	return $code;

}

################################################################################

sub the_rest_of_the_script () {

	my @code = ();

	my $flag = 0;

	open (SCRIPT, $0);

	while (<SCRIPT>) {

		if    (/use\s+Eludia::Offline/) { $flag = 1 }

		else                            { $code [$flag] .= $_ }

	}

	close (SCRIPT);

	return $code [1] || $code [0];

}

################################################################################

BEGIN {

	$| = 1;

	my $code = perl_section_from config_file;

	eval $code; die "$code\n\n$@" if $@;

	my $package = __PACKAGE__;

	$package = $Eludia::last_loaded_package if $package eq 'main';

	initialize_offline_script_execution (${$package . '::preconf'});

	$code = qq {

		package $package;

		\$_REQUEST {__skin} = 'STDERR';

		our \$i18n = i18n ();

		sql_reconnect ();

		require_model ();

		no warnings;

	} . the_rest_of_the_script;

	eval $code; die "$code\n\n$@" if $@;

	finalize_offline_script_execution;

	exit;

}

1;
