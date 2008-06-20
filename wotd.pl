#!/usr/bin/perl

use strict;
use warnings;

use WWW::Mechanize;
use XML::TreePP;

# variables - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# google calendar web service
my $calendarURL = "http://www.google.com/calendar/feeds/j59p2p5a1rbkvaglvednl7ouas%40group.calendar.google.com/public/basic";

# sonic links
my $loginURL = "http://www.radiosonic.fm";
my $wotdURL = "http://www.m2omedia.com/chdi/members/earn/trivias.jsp";
my $blurbURL = "http://www.m2omedia.com/chdi/members/earn/bonuscodes.jsp";

# basic application logging - setting this variable to 1 will log 
# various actions to STDERR
my $LOG = 1;

# main - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 

die "Missing arguments! You must provide at least one username:password pair\n" .
    " Usage: ./$0 <username1>:<password1> [<username2>:<password2> <username3>:<password3> ... <usernameN>:<passwordN>]\n"
	unless scalar @ARGV >= 1;

# determine the current date in ISO-8601 format (used by google calendar :))
my @Specs = localtime();
my $date = $Specs[5]+1900 . "-" . sprintf("%02d", $Specs[4]+1) . "-" . sprintf("%02d", $Specs[3]); # yyyy-mm-dd

print STDERR "$date: let the scrapping begin!\n";

# create parser and set a few default options
my $parser = XML::TreePP->new();
$parser->set
(
	user_agent => "Mozilla/4.76 [en] (Win98; U)",
	force_array => ['entry'],
);

# retrieve the xml resource, parse it, and generate a hash
my $tree = $parser->parsehttp(GET => $calendarURL);

my $wotd = "";
my @Blurbs;
foreach my $entry (@{$tree->{feed}{entry}})
{
	print STDERR "Entry date: " . $entry->{published} . " <=> $date\n" if $LOG;

	# break out if we've hit entries that don't have
	# todays date YYYY-MM-DD
	last unless $entry->{published} =~ /^$date/;
		
	my $text = $entry->{title}{'#text'};
	print STDERR "Entry text: $text\n" if $LOG;

	# check entry text for blurb word
	# if found, add to list
	if ($text =~ /blurb/gi)
	{
		if ($text =~ /^((\s*\w+)+)/)
		{
			push @Blurbs, $1;
			print STDERR "Found blurb: '$1'\n" if $LOG;
		}
	}

	# since its not a blurb word, its either the wotd or 
	# an entry regarding "Whats In The Van Man?"
	else
	{
		# only "Whats In The Van Man?" entries START with "Van Man".
		# If this entry isn't one of those, it must be a wotd entry.
		unless ($text =~ /^van man/gi)
		{
			if ($text =~ /^((\s*\w+)+)/) 
			{ 
				$wotd = $1;
				print STDERR "Found wotd: '$1'\n" if $LOG;
			}
		}
	}
}

# if we've found at least one thing that can be processed,
# proceed with the login
if ($wotd or scalar @Blurbs)
{
	foreach my $pair (@ARGV)
	{
		# check command line argument to ensure that its as expected (username:password)
		next unless $pair =~ /^(\w+):(\w+)$/g;

		my $username = $1;
		my $password = $2;

		my $browser = WWW::Mechanize->new(onwarn => undef);
		$browser->agent_alias("Windows Mozilla");

		print STDERR "Setting default useragent: " . $browser->agent() . "\n" if $LOG;

		# login to gleeclub 2.0!
		$browser->get($loginURL);
		my $response = $browser->submit_form
		(
			form_name => "login",
			fields => 
			{
				username => $username,
				password => $password,
			},
		);

		# check to ensure that we were successfully logged in...
		if ($response->content() =~ /you're logged in as/gi)
		{
			print STDERR "Successfully logged in as: $username\n" if $LOG;
		}
		else
		{
			print STDERR "Failure! Unable to log in as: $username\n" if $LOG;
			next;
		}

		# submit the wotd if we have one
		if ($wotd)
		{
			$response = $browser->get($wotdURL);

			# HACK ALERT - not sure why but for some reason WWW::Mechanize doesn't
			# seem to like the data that gets returned when it requests the wotd or blurb
			# pages (via HTTP GET).  The html is properly formatted but it seems to have 
			# troubles parsing and extracting the form elements.  Passing the raw html
			# to update_html() forces Mechanize to reparse the page which corrects the issue.
			$browser->update_html($response->content());

			if ($browser->form_name('playtrivia'))
			{
				$browser->field('answer' => $wotd);
				$response = $browser->submit();

				# check response for the word 'congratulations'.  If it appears, wotd was successfully posted
				if ($response->content() =~ /congratulations/gi) 
				{ 
					print "Successfully submitted wotd: $wotd\n";
					print STDERR "Successfully submitted wotd: $wotd\n" if $LOG;
				}
				else 
				{ 
					print STDERR "Submission of wotd ($wotd) failed! It must have been the wrong word...\n" 
						if $LOG;
				}

				#print STDERR $response->content() . "\n"
				#	if $LOG;
			}
			else
			{
				print STDERR "Couldn't find wotd form field, must have submitted already...\n" if $LOG;
			}
		}

		# loop through the list of blurb words (if any)
		# and submit each one
		foreach my $blurb (@Blurbs)
		{
			$browser->get($blurbURL);
			$browser->update_html($browser->content());

			$response = $browser->submit_form
			(
				form_name => "playbc",
				fields => { code => $blurb },
			);

			# check the response for the blurb word.  If it appears, the blurb was successfully posted
	 		if ($response->content() =~ /$blurb/gi)
			{
				print "Successfully submitted blurb: $blurb\n";
				print STDERR "Successfully submitted blurb: $blurb\n" if $LOG;
			}
			else
			{
				print STDERR "Submission of blurb ($blurb) failed! It may have already been submitted...\n"
					if $LOG;
			}

			#print STDERR $response->content() . "\n"
			#	if $LOG;
		}

		# print out current sonic points balance
		if ($response->content() =~ m#<strong>([\w,]+)\ssonic\spoints</strong>#gi)
		{
			print "Current balance for $username: $1\n";
			print STDERR "Current balance for $username: $1\n" if $LOG;
		}
	}
}

