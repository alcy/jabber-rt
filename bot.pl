use strict;
use warnings;
use AnyEvent::XMPP::Client;
use AnyEvent::XMPP::Ext::Disco;
use AnyEvent::XMPP::Ext::Version;
use AnyEvent::XMPP::Ext::MUC;
use RT::Client::REST;
use DateTimeX::Easy;
use Data::Dumper::Perltidy;
$| = 1;


# USAGE
# !rt id=123

my $client = AnyEvent::XMPP::Client->new();
my $j = AnyEvent->condvar;
my $rturl;
my $rt_timezone; # timezone that is configured to be used by rt
my $timezone; # if rt box is in a differernt timezone than you need, set this param to desired tz
my $rt = RT::Client::REST->new(
  server => $rturl, # 'http://rt.foo.com'
  timeout => 30
);
my $disco   = AnyEvent::XMPP::Ext::Disco->new;
my $muc     = AnyEvent::XMPP::Ext::MUC->new (disco => $disco);

my $rt_user;
my $rt_pass;
my $rt_ticket = sub { 
  my $id = shift;
  $rt->login(username => $rt_user, password => $rt_pass);
  my $ticket = $rt->show(type => 'ticket', id => "$id");
  return $ticket;
};

my $datemanip = sub {
  my $date = shift;
  $date = $date . " $rt_timezone"; # needs to be appended for conversion
  my $dt = DateTimeX::Easy->parse($date);
  $dt->set_time_zone($timezone);
  return $dt->day_abbr . " " . $dt->month_abbr . " " . $dt->day . " " . $dt->hms;
};
  
my $mainreply = sub { 
  my ( $msg, $ticket ) = @_;
  my $reply = $msg->make_reply;
  my ( $queue, $subject, $owner, $created, $lastupdated ) = ( $ticket->{Queue}, $ticket->{Subject}, $ticket->{Owner}, $ticket->{Created}, $ticket->{LastUpdated} );
  $created = $datemanip->($created);
  $lastupdated = $datemanip->($lastupdated);
  $reply->add_body("Ticket \"$subject\" in queue $queue, was created on $created, last updated on $lastupdated, and is owned by $owner\n");
  $reply->send;
};

my $tmpreply = sub { 
  my $msg = shift;
  my $reply = $msg->make_reply;
  $reply->add_body("Getting data, please wait.");
  $reply->send;
};

my $parsemsg = sub { 
  my $msg = shift;
  my $body = $msg->body;
  if ( $body =~ /^\!rt/ ) { 
    $tmpreply->($msg);
    # get id, process
    my ($id) = ( $body =~ /(?:^\!rt) id=(\d+)/ );
    return $id;
  }
};

my $jabber_user; # user@domain
my $jabber_pass;
my @jabber_rooms; # test@conference.localhost
my $jabber_room_nick; # desired nick in the room

$client->add_extension($disco);
$client->add_extension($muc);
$client->add_account($jabber_user, $jabber_pass);

$client->reg_cb( 
  session_ready => sub { 
    my ( $cl, $acc ) = @_;
    for my $room ( @jabber_rooms ) { 
      $muc->join_room($acc->connection, $room, $jabber_room_nick, { history => { chars => 0 } });
    }
    $muc->reg_cb(
      message => sub { 
        my ( $cl, $acc, $msg, $is_echo ) =  @_;
        return if $is_echo;
        return if $msg->is_delayed;
        my $id = $parsemsg->($msg);
        my $ticket = $rt_ticket->($id);
        $mainreply->($msg, $ticket); 
      },
    );
  }
);

$client->start;
$j->wait;


