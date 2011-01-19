#!/usr/bin/perl

# Copyright 2011 Patrick Schoenfeld <schoenfeld@debian.org>
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;

use File::Basename;
use Net::OpenXchange;
use Net::Google::Calendar;
use List::Util qw(first);
use DateTime;
use Data::Dumper;
use Getopt::Long;
use YAML qw(LoadFile);
use Env qw(HOME);

my $progname = basename($0);
# Locate and load configuration
my $cfg_file;
foreach my $file qw( .config/ox2gcalendar/ox2gcalendar.cf .ox2gcalendar.cf ) {
    my $file_path = $HOME . "/" . $file;
    if ( -e $file_path ) {
        $cfg_file = $file_path;
    }
}
if (not $cfg_file) {
    print STDERR "$progname: need a configuration file, please have a look at the manpage.\n";
    exit(1);
}
my ($cfg) = LoadFile($cfg_file) or die "$progname: unable to open configuration file ($cfg_file): $!";

my $ox_uri = $cfg->{ox_uri};
my $ox_login = $cfg->{ox_login};
my $ox_password = $cfg->{ox_password};
my $ox_folder_path = $cfg->{ox_folder_path};
my $ox_calendar = $cfg->{ox_calendar};
my $google_login = $cfg->{google_login};
my $google_password = $cfg->{google_password};
my $google_calendar = $cfg->{google_calendar};

my $opt_extract_months = $cfg->{extract_months} || "1";
my $opt_masquerade_title = $cfg->{masquerade_title} || 0;
my $opt_masquerade_string = "Geschäftstermin";

my $opt_debug=0;
my $opt_verbose=0;

GetOptions(
    "debug|d" => \$opt_debug,
    "verbose|v" => \$opt_verbose
);

sub debugmsg {
    my $msg = shift;
    print STDERR "DEBUG: " . $msg . "\n" if $opt_debug;
}
sub printmsg {
    my $msg = shift;
    print $msg . "\n" if $opt_verbose;
}

# Initialize OX connection
debugmsg "Logging into OX, using login: $ox_login and password: ********";
my $ox = Net::OpenXchange->new(uri => $ox_uri, login => $ox_login, password => $ox_password);
my $folder = $ox->folder->resolve_path($ox_folder_path, $ox_calendar);
my @appointments = $ox->calendar->all(
    folder => $folder,
    start => DateTime->now()->truncate( to => 'day' ),
    end => DateTime->now()->truncate( to => 'day')->add(months => $opt_extract_months)
);

# Initialize google calendar conncetion
debugmsg "Logging into Google Calendar, using login: $ox_login and password: ********";
my $gcalendar = Net::Google::Calendar->new;
$gcalendar->login($google_login, $google_password);

# Find the right google calendar
my $gcal_obj;
$gcal_obj = first { $_->title eq $google_calendar } ($gcalendar->get_calendars);
$gcalendar->set_calendar($gcal_obj);
debugmsg "Selected google calendar id " . $gcal_obj->id;
debugmsg "Found " . scalar(@appointments) . " appointments in OX.";

# Find entries already stored in google calendar
debugmsg "Google calendar " . $gcal_obj->title . " has " .scalar($gcalendar->get_events) . " entries.";
my $gcal_appointments = {};
foreach my $gcal_appointment ($gcalendar->get_events) {
    my $extended_props = $gcal_appointment->extended_property();
    if ($extended_props->{'ox-id'}) {
        my $id = $extended_props->{'ox-id'};
        debugmsg "Found existing OX appointment #$id";
        $gcal_appointments->{$id} = $gcal_appointment;
    }
}

my $new_entries=0;
my $updated_entries=0;
foreach my $appointment (@appointments) {
    my $title = $appointment->title;
    $title = $opt_masquerade_string if $opt_masquerade_title;
    my $id = $appointment->id;
    my $start_date = $appointment->start_date;
    my $end_date = $appointment->end_date;
    my $all_day = $appointment->full_time;

    debugmsg "Found Appointment #$id: " . $start_date. " - " . $end_date . " $title";
    my $gcal_appointment = (defined $gcal_appointments->{$id}) ? $gcal_appointments->{$id} : Net::Google::Calendar::Entry->new();
    $gcal_appointment->title($title);
    $gcal_appointment->when($appointment->start_date, $appointment->end_date, $all_day);
    $gcal_appointment->visibility("private");
    $gcal_appointment->extended_property("ox-id", $appointment->id);

    if (defined $gcal_appointments->{$id}) {
        debugmsg "Entry $id is old. Updating it.";
        $gcalendar->update_entry($gcal_appointment);
        $updated_entries++;
    } else {
        debugmsg "Entry $id is new.";
        $gcalendar->add_entry($gcal_appointment);
        $new_entries++;
    }
}
printmsg "Added $new_entries new entries/Updated $updated_entries existing entries in Google Calendar '" . $gcal_obj->title . "'.";

# vim: expandtab:ts=4:sw=4
