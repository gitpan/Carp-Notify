package Carp::Notify;

#Copyright (c) 2000 James A Thomason III (thomasoniii@yahoo.com). All rights reserved.
#This program is free software; you can redistribute it and/or
#modify it under the same terms as Perl itself.


$VERSION = "1.00";

use 5.004;	#probably lower, but I haven't tested it below 004
#use Socket;
#use strict;
#$^W = 1;

my $def_smtp 		= "your.smtp.com";	#<--IMPORTANT!  Set this!

my $def_email_it	= 1;
my $def_email 		= 'thomasoniii@yahoo.com';
my $def_return		= 'thomasoniii@yahoo.com';
my $def_subject 	= "Ye Gods!  An error!";
my $def_domain		= "smtp.com";		#<--IMPORTANT!  Set this! I mean it!

my $def_log_it 		= 1;
my $def_log_file 	= "error.log";

my $def_store_vars	= 1;
my $def_stack_trace	= 1;
my $def_store_env	= 1;

#die_to_stdout is important.  Since a lot of CGI scripts will be using this thing, it will be
#very helpful to die with some message to the browser, if so desired.  Of course, this module
#is also very useful for cron jobs or other things that are running in the background where
#we probably don't want to die to STDOUT, or possibly at all.  Set everything here to reflect
#that

my $def_die_to_stdout	= 0;

#Don't die with a message to STDERR or STDOUT.  Just let the explosion log and the email
#suffice.
my $def_die_quietly		= 0;

#What would you like to die with?  This is probably the message that's going to your user in
#his browser, so make it something nice.  You'll have to set the content type yourself, though.
#Why's that, you ask?  I wanted to be sure that you had the option of easily redirecting to 
#a different page if you'd prefer.

my $def_death_message   = <<eoE;
Content-type:text/plain\n\n

We're terribly sorry, but some horrid internal error seems to have occurred.  We are actively
looking into the problem and hope to repair the error shortly.  We're sorry for any inconvenience.

eoE

#end defaults.  Don't mess with anything else!

my $settables = "(?:log_it|email_it|store_vars|stack_trace|store_env|email|log_file|smtp|die_to_stdout|die_quietly|death_message)";

BEGIN {
	$Carp::Notify::can_email = 1;
	eval "use Socket";
	$Carp::Notify::can_email = 0 if $@;
	
	$Carp::Notify::fatal = 1;	#doesn't really belong here, but the cleanest place to put it...
};


{
	no strict 'refs';
	my $calling_package = undef;
	
	my %storable_vars = ();
	
	my @storable_vars = ();
	my %init = ();
	
	
	sub import {
		my ($package, $file, $line) = caller;
		$calling_package = $package;
		
		*{$package . "::explode"} = \&Carp::Notify::explode;
		*{$package . "::notify"} = \&Carp::Notify::notify;

		#foreach my $var (@_){
		while (defined (my $var = shift)){
			if ($var eq ""){die ("Error...tried to import undefined value in $file, Line $line\n")};
			
			if ($var =~ /^$settables$/o){
				$init{$var} = shift;
				next;
			};
			
			push @storable_vars, $var if $var =~ /^[\$@%]/;
			push @{$storable_vars{$calling_package}}, $var if $var =~ /^[\$@%]/;
			
			#see if we want to overload croak or export anything while we're at it.
			#sub {shift->accessor($prop,  @_)};
			*{$package . "::croak"}   			= \&Carp::Notify::explode if $var eq "croak";
			*{$package . "::carp"}   			= \&Carp::Notify::notify if $var eq "carp";
			*{$package . "::make_storable"}   	= \&Carp::Notify::make_storable if $var eq "make_storable";
			*{$package . "::make_unstorable"}   = \&Carp::Notify::make_unstorable if $var eq "make_unstorable";
		};
		
		print map {"--> $_: @{$storable_vars{$_}}\n"} keys %storable_vars;
	};

	sub store_vars {
		my $stored_vars = "";
		my $calling_package = (caller(1))[0];	#eek!  This may bite me in the ass.
		
		#foreach my $storable_var (@storable_vars){
		foreach my $storable_var (@{$storable_vars{$calling_package}}){
						
			my $type = $1 if $storable_var =~ s/([\$@%])//;
			
			my $package = $calling_package . "::";
			   $package = $1 if $storable_var =~ s/(.+::)//; 

			
			print "STORABLE : $package$storable_var\n\n";
			
			if ($type eq '$') {
				my $storable_val = ${$package . "$storable_var"};
				$stored_vars .= "\t\$${package}$storable_var : $storable_val\n";next;
			
			}
			elsif ($type eq '@') {
				my @storable_val = @{$package . "$storable_var"};
				$stored_vars .= "\t\@${package}$storable_var : (@storable_val)\n";next;
				
			}
			elsif ($type eq '%') {
				my %temp_hash = %{$package . "$storable_var"};
				my @storable_val =  map {"\n\t\t$_ => $temp_hash{$_}"} keys %temp_hash;
				$stored_vars .= "\t\%${package}$storable_var : @storable_val\n";next;
			
			};

		};
		
		return $stored_vars;
		
	};
	
	sub make_storable {
		foreach my $var (@_){
			push @storable_vars, $var if $var =~ /^[\$@%]/;;
		};
		return 1;	
	};
	
	sub make_unstorable {
		my $no_store = join("|", map {quotemeta} @_);
		@storable_vars = grep {!/^(?:$no_store)$/} @storable_vars;
		return 1;
	};
	
	#hee hee!  Remember, a notification is just an explosion that isn't fatal.  So we use are nifty handy dandy
	#fatal class variable to tell explode that it's not a fatal error.  explode() will set fatal back to 1 once
	#it realizes that errors are non-fatal.  That way a future explosion will still be fatal.
	sub notify {
		$Carp::Notify::fatal = 0;
		goto &explode;
	};

	sub explode {

		#my %init = @_;
		my $errors = undef;
		
		while (defined (my $arg = shift)) {
			if ($arg =~ /^$settables$/o){
				$init{$arg} = shift;
			}
			else {$errors .= "\t$arg\n"};
		};
		
		my $log_it   	= defined $init{"log_it"} 		? $init{"log_it"}		: $def_log_it;
		my $email_it   	= defined $init{"email_it"} 	? $init{"email_it"}		: $def_email_it;

		my $store_vars	= defined $init{"store_vars"} 	? $init{"store_vars"} 	: $def_store_vars;
		my $stack_trace = defined $init{"stack_trace"} 	? $init{"stack_trace"}	: $def_stack_trace;
		my $store_env	= defined $init{"store_env"} 	? $init{"store_env"} 	: $def_store_env;

		my $email 	 	= $init{"email"} 			|| $def_email;
		my $log_file	= $init{"log_file"} 		|| $def_log_file;
		my $smtp	 	= $init{'smtp'}				|| $def_smtp;
		
		my $stored_vars = store_vars()  if $store_vars;
		my $stack 		= stack_trace() if $stack_trace;
		my $environment	= store_env()   if $store_env;
		
		my $die_to_stdout = defined $init{"die_to_stdout"} 	? $init{"die_to_stdout"} 	: $def_die_to_stdout;
		my $die_quietly   = defined $init{"die_quietly"} 	? $init{"die_quietly"} 	: $def_die_quietly;
		my $death_message = $init{'death_message'}			|| $def_death_message;
		
		my $message = "";
		
		$message .= "An error occurred on " . today() . "\n";
		
		$message .= "\n>>>>>>>>>\nERROR MESSAGES\n>>>>>>>>>\n\n$errors\n<<<<<<<<<\nEND ERROR MESSAGES\n<<<<<<<<<\n" 		if $errors;
		$message .= "\n>>>>>>>>>\nSTORED VARIABLES\n>>>>>>>>>\n\n$stored_vars\n<<<<<<<<<\nEND STORED VARIABLES\n<<<<<<<<<\n"if $stored_vars;	
		$message .= "\n>>>>>>>>>\nCALL STACK TRACE\n>>>>>>>>>\n\n$stack\n<<<<<<<<<\nEND CALL STACK TRACE\n<<<<<<<<<\n" 		if $stack_trace;
		$message .= "\n>>>>>>>>>\nENVIRONMENT\n>>>>>>>>>\n\n$environment\n<<<<<<<<<\nEND ENVIRONMENT\n<<<<<<<<<\n" 			if $store_env;
		
		log_it(
			"log_file" => $log_file,
			"message" => $message
		) if $log_it;
		
		simple_smtp_mailer(
			"email" => $email,
			"message" => $message
		) if $email_it;
		if ($Carp::Notify::fatal){
			if ($die_quietly){
				exit;
			}
			else {
				if ($die_to_stdout){
					print $death_message;
					exit;
				}
				else {die $death_message};
			};
		}
		else {
			$Carp::Notify::fatal = 1;
			return undef;
		};
	};

	
};




#psst!  If you're looking for store_vars, it's up at the top wrapped up with import!	

sub store_env {
	my $env = undef;
	foreach (sort keys %ENV){
		$env .= "\t$_ : $ENV{$_}\n";
	};
	return $env;
};
	

sub stack_trace {
	my $caller_count = 1;
	my $caller_stack = undef;
	my @verbose_caller = ("Package: ", "Filename: ", "Line number: ", "Subroutine: ", "Has Args? : ",
							"Want array? : ", "Evaltext: ", "Is require? : ");
	
	while (my @caller = caller($caller_count++)){
		$caller_stack .= "\t---------\n";
		foreach (0..$#caller){
			$caller_stack .= "\t\t$verbose_caller[$_]$caller[$_]\n" if $caller[$_];
		};
	};

	$caller_stack .= "\t---------\n";
	return $caller_stack;
};

sub log_it {
	my %init = @_;
	
	my $log_file = $init{log_file};
	my $message  = $init{message};
	
	local *LOG;
	
	if (! ref $log_file){
		open (LOG, ">>$log_file") or error ("Cannot open log file: $!");
	}
	else {
		*LOG = $log_file;
	};
	
	print LOG "\n__________________\n$message\n__________________\n";
	if (! ref $log_file){close LOG or error ("Cannot close log file: $!")};
};

sub simple_smtp_mailer {

	error ("Cannot email: Socket.pm could not load!") unless $Carp::Notify::can_email;

	my %init = @_;
	my $email	= $init{"email"} || $def_email;
	my $smtp 	= $init{"smtp"}  || $def_smtp;
	my $message = $init{"message"};

	local *MAIL;
	my $response = undef;	
	my ($s_tries, $c_tries) = (5, 5);
	local $\ = "\015\012";
	local $/ = "\015\012";

	#connect to the server
	1 while ($s_tries-- && ! socket(MAIL, PF_INET, SOCK_STREAM, getprotobyname('tcp')));
	return error("Socket error $!") if $s_tries < 0;
	
	my $remote_address = inet_aton($smtp);
	my $paddr = sockaddr_in(25, $remote_address);
	1 while ! connect(MAIL, $paddr) && $c_tries--;
	return error("Connect error $!") if $c_tries < 0;
	
	#keep our bulk pipes piping hot.
	select((select(MAIL), $| = 1)[0]);
	#connected

	#build the envelope
	my @conversation =
		(
			["", "No response from server: ?"],
			["HELO $def_domain", "Mean ole' server won't say HELO: ?"],
			["RSET", "Cannot reset connection: ?"],
			["MAIL FROM:<$def_return>", "Invalid Sender: ?"],
			["RCPT TO:<$email>", "Invalid Recipient: ?"],
			["DATA", "Not ready to accept data: ?"]
		);

	while (my $array_ref = shift @conversation){
		my ($i_say, $i_die) = @{$array_ref};
		print MAIL $i_say if $i_say;
		my $response = <MAIL> || "";

		if (! $response || $response =~ /^[45]/){
			$i_die =~ s/\?/$response/;
			return error($i_die);
		};
		return error("Server disconnected: $response") if $response =~ /^221/;

	};
	#built
	
	#send the data
	print MAIL "Date: ", today();
	print MAIL "From: $def_return";
	print MAIL "Subject: $def_subject";
	print MAIL "To: $email";
	print MAIL "X-Priority:2  (High)";
	print MAIL "X-Carp::Notify: $Carp::Notify::VERSION";
	
	print MAIL "";	$message =~ s/^\./../gm;
	$message =~ s/\r?\n/\015\012/g;
	#print "MESSAGE\n(\n$message\n)\n";
	
	print MAIL $message;

	print MAIL ".";
	#sent
	
	return 1;	#yay!
};

sub today {
	
	my @months 	= qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	my @days 	= qw(Sun Mon Tue Wed Thu Fri Sat);
	
	my ($sec, $min, $hour, $mday, $mon, $year, $wday) = localtime(time);
	
	$hour = "0" . $hour if $hour < 10;
	$min  = "0" . $min  if $min < 10;
	$sec  = "0" . $sec if $sec < 10;
	$year += 1900;		#RFC 1123 dates are 4 digit!
	
	my($gmin, $ghour, $gsdst) = (gmtime(time))[1,2, -1];

	(my $diffhour = sprintf("%03d", $hour - $ghour)) =~ s/^0/\+/;
	
	return "$days[$wday], $mday $months[$mon] $year $hour:$min:$sec " . $diffhour . sprintf("%02d", $min - $gmin);
	
};


#I haven't decided what to do with error.  It's hanging around in case I think of a clever way to handle errors within
#the module.  But, of course, how does the error reporting module report an error reporting an error?...
sub error { undef};


1;

__END__

=pod

=head1 NAME

Carp::Notify - Loudly complain in lots of places when things break badly

=head1 AUTHOR

Jim Thomason thomasoniii@yahoo.com

=head1 SYNOPSIS

Use it in place of die or croak, or warn or carp.

 #with Carp;
 use Carp;
 if ($something_a_little_bad) { carp("Oh no, a minor error!")};
 if ($something_bad) { croak ("Oh no an error!")};


 #with Carp::Notify;
 use Carp::Notify;
 if (something_a_little_bad) {notify("Oh no, a minor error!")};
 if ($something_bad) { explode ("Oh no an error!")};

=head1 REQUIRES

Perl 5.004, Socket (for emailing)

=head1 DESCRIPTION

Carp::Notify is an error reporting module designed for applications that are running unsupervised (a CGI script, for example,
or a cron job).  If a program has an explosion, it terminates (same as die or croak or exit, depending on preference) and 
then emails someone with useful information about what caused the problem.  Said information can also be logged to a file.
If you want the program to tell you something about an error that's non fatal (disk size approaching full, but not quite
there, for example), then you can have it notify you of the error but not terminate the program.

Defaults are set up within the module, but they can be overridden once the module is used, or as individual explosions take place.

=head1 BUILT IN STUFF

=over 11

=item Using the module

use Carp::Notify;

will require and import the module, same as always.  What you decide to import it with is up to you.  You can choose to import
additional functions into your namespace, set up new default values, or give it a list of variables to store.

Carp::Notify will B<always> export the explode function and the notify function.  Carp always exports carp, croak, and confess,
so I figure that I can get away with always exporting explode and notify.  Nyaah.

Be sure that you set your default variables before using it!

=over 3

=item make_storable

if this is an import argument, it will export the make_storable function into your namespace.  See make_storable, below.

=back

=over 3

=item make_unstorable

If this is an import argument, it will export the make_unstorable function into your namespce.  See make_unstorable, below.

=back

=over 3

=item croak

If this is an import argument, it will override the croak function in your namespace and alias it to explode.  That way
you can switch all of your croaks to explodes by just changing how you use your module, and not all of your code.

=back

=over 3

=item carp

If this is an import argument, it will override the carp function in your namespace and alias it to notify.  That way
you can switch all of your carps to notifies by just changing which module you use, and not all of your code.

=back

=over 3

=item (log_it|email_it|store_vars|stack_trace|store_env|email|log_file|smtp|die_to_stdout|die_quietly|death_message)

Example:

 use Carp::Notify (
 	"log_it" => 1,
 	"email_it => 0,
 	"email" => 'thomasoniii@yahoo.com'
 );

These are hash keys that allow you to override the Carp::Notify's module defaults.  These can also all be overloaded explicitly
in your explode() calls, but this allows a global modification.

=over 2

=item log_it

Flag that tells Carp::Notify whether or not to log the explosions to the log file

=back

=over 2

=item log_file

Overrides the default log file.  This file will be opened in append mode and the error
message will be stored in it, if I<log_it> is true.

If you'd like, you can give log_file a reference to a glob that is an open filehandle instead
of a scalar containing the log name.  This is most useful if you want to redirect your error log
to STDERR or to a pipe to a program.

Be sure to use globrefs only explicitly in your call to explode, or to wrap the definition of the
filehandle in a begin block before using the module.  Otherwise, you'll be trying to log to
a non-existent file handle and consequently won't log anything.  That'd be bad.

=back

=over 2

=item email_it

Flag that tells Carp::Notify whether or not to email a user to let them know something broke

=back

=over 2

=item email

Overrides the default email address.  This is whoever the error message will get emailed to
if U<email_it> is true.

=back

=over 2

=item smtp

Allows you to set a new SMTP relay for emailing

=back

=over 2

=item store_vars

Flag that tells Carp::Notify whether or not to list any storable variables in the error message.  See storable variables, below.

=back

=over 2

=item stack_trace

Flag that tells Carp::Notify whether or not to do a call stack trace of every function call leading up to the explosion.

=back

=over 2

=item store_env

Flag that tells Carp::Notify whether or not to store the environment variables in the error message.

=back

=over 2

=item die_to_stdout

Allows you to terminate your program by displaying an error to STDOUT, not to STDERR.

=back

=over 2

=item die_quietly

Terminates your program without displaying any message to STDOUT or STDERR.
=back

=over 2

=item death_message

The message that is printed to the appropriate location, unless we're dying quietly.
=back

=back

=over 3

=item (I<storable variable>)

A variable name within B<single> quotes will tell the Carp::Notify module that you want to report the current value of that variable when
the explosion occurs.  Carp::Notify will report an error if you try to store a value that is undefined, if you had accidentally
typed something in single quotes, for instance.  For example,

 use Carp::Notify ('$scalar', '@array');
 
 $scalar = "some_value";
 @array = qw(val1 val2 val3);
 
 explode("An error!");
 
will write out the values "$scalar : some_value" and "@array : val1 val2 val3" to the log file.

This can also only be used to store global variables. Dynamic or lexical variables need to be explicitly placed in explode() calls.

You can store variables from other packages if you'd like:

use Carp::Notify ('$other_package::scalar', '@some::nested::package::array');

Only I<global> scalars, arrays, and hashes may be stored.

=back

=back

=over 11

=item make_storable

Makes whatever variables it's given storable.  See I<storable variables>, above.

 make_storable('$new_scalar', '@different_array');

=back

=over 11

=item make_unstorable

Stops whatever variables it's given from being stored.  See I<storable variables>, above.

 make_unstorable('$scalar', '@different_array');

=back

=over 11

=item explode

explode is where the magic is.  It's exported into the calling package by default (no point in using this module if you're
not gonna use this function, after all).

You can override your default values here (see I<Using the module above>), if you'd like, and otherwise specify as many error messages
as you'd like to show up in your logs.

 #override who the mail's going to, and the log file.
 explode("email" => "thomasoniii@yahoo.com", log_file => "/home/jim/jim_explosions.log", "A terrible error: $!");

 #Same thing, but with a globref to the same file
 open (LOG, ">>/home/jim/jim_explosions.log");
 explode("email" => "thomasoniii@yahoo.com", log_file => \*LOG, "A terrible error: $!");


 #don't log.
 explode ("log_it" => 0, "A terrible error: $!");
 
 #keep the defaults
 explode("A terrible error: $!", "And DBI said:  $DBI::errstr");

=back

=over 11

=item notify

notify is to explode as warn is to die.  It does everything exactly the same way, but it won't terminate your program the
way that an explode would.

=head1 FAQ

B<So what's the point of this thing?>

It's for programs that need to keep running and that need to be fixed quickly when they break.

B<But I like Carp>

I like Carp too.  :)

This isn't designed to replace Carp, it serves a different purpose.  Carp will only tell you the line on which your error occurred.
While this i helpful, it doesn't get your program running quicker and it doesn't help you to find an error that you're not aware of
in a CGI script that you think is running perfectly.

Carp::Notify tells you ASAP when your program breaks, so you can inspect and correct it quicker.  You're going to have less downtime
and the end users will be happier with your program because there will be fewer bugs since you ironed them out quicker.

B<Wow.  That was a real run-on sentence>

Yeah, I know.  That's why I'm a programmer and not an author.  :)

B<What about CGI::Carp?>

That's a bit of a gray area.  Obviously, by its name, CGI::Carp seems designed for CGI scripts, whereas Carp::Notify is more
obvious for anything (cron jobs, command line utilities, as well as CGIs).

Carp::Notify also can store more information with less interaction from the programmer.  Plus it will email you, if you'd like
to let you know that something bad happened.

As I understand it, CGI::Carp is a subset feature-wise of Carp::Notify.  If CGI::Carp is working fine for you, great continue to use
it.  If you want more flexible error notification, then try out Carp::Notify.

B<But I can send email with CGI::Carp by opening up a pipe to send mail and using that as my error log.  What do you have
to say about that?>

Good for you.  I can too.  But most people that I've interacted with either don't have the know-how to do that or just plain
wouldn't have thought of it.  Besides, it's still more of a hassle than just using Carp::Notify.

B<Why are your stored variables kept in an array instead of a hash?  Hashes are quicker to delete from, after all>

While it is definitely true that variables can be unstored a little quicker in a hash, I figured that stored variables 
will only rarely be unstored later.  Arrays are quicker for storing and accessing the items later.   I'll live with the
slight performance hit for the rarer case.

B<Can I store variables that are in another package from the one that called Carp::Notify?>

You betcha.  Just prepend the classpath to the variable name, same as you always have to to access variables not in your name
space.  If the variable is already in your name space (you imported it), you don't need the classpath since explode will
just pick it up within your own namespace.

B<Can I store local or my variables?>

Not in the use statement, but you can in an explicit explode.

B<Are there any bugs I should be aware of?>

Only if you're annoying.  If you import explode into your package, then subclass it and export explode back out it won't correctly
pick up your stored variables unless you fully qualified them with the class path ($package::variable instead of just $variable)

Solution?  Don't re-export Carp::Notify.  But you already knew that you should juse re-use it in your subclass, right?

B<Could I see some more examples?>

Sure, that's the next section.

B<Okay, you've convinced me.  What other nifty modules have you distributed?>

Mail::Bulkmail and Text::Flowchart.

B<Was that a shameless plug?>

Why yes, it was.

=head1 Examples

 #store $data, do email the errors, and alias croak => explode
 use Carp::Notify ('$data', 'email_it' => 1, "croak");

 #email it to a different address, and don't log it.
 use Carp::Notify ("email" => 'thomasoniii@yahoo.com', 'log_it' => 0);

 #die with an explosion.
 explode("Ye gods!  An error!");
 
 #explode, but do it quietly.
 explode ("die_quietly" => 1, "Ye gods!  An error!");
 
 #notify someone of a problem, but keep the program running
 notify ("Ye gods!  A little error!");

=head1 Version History

=over 11

v1.00 - August 10, 2000 - Changed the name from Explode to Carp::Notify.  It's more descriptive and I don't create a new namespace.

v1.00 FC1 - June 9, 2000 - First publically available version.

=head1 COPYRIGHT (again)

Copyright (c) 2000 James A Thomason III (thomasoniii@yahoo.com). All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 CONTACT INFO

So you don't have to scroll all the way back to the top, I'm Jim Thomason (thomasoniii@yahoo.com) and feedback is appreciated.
Bug reports/suggestions/questions/etc.  Hell, drop me a line to let me know that you're using the module and that it's
made your life easier.  :-)

=cut


