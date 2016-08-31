package Kernel::System::Request;

use warnings;
use strict;
use LWP::UserAgent;
use HTTP::Request::Common qw{ POST };
use Kernel::System::ObjectManager;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( %Param ) = @_;

    my $url      = 'http://localhost/otrs/nph-genericinterface.pl/Webservice/ConnectorREST/CustomerUser?UserLogin=admin&Password=1write3';
my $content  = "{\"CustomerUser\":{\"UserLogin\":\"userlogin\", \"UserPassword\":\"passwd\", \"UserFirstname\":\"firstname1\", \"UserLastname\":\"lastname1\", \"UserCustomerID\":\"'$Param{UserCustomerID}'\", \"UserEmail\":\"email\@mail.ru\", \"ValidID\":\"1\"}}";

my $ua       = LWP::UserAgent->new();
my $request  = HTTP::Request->new(POST => $url);
$request->header('content-type' => 'application/json');
$request->content($content);
my $response = $ua->request($request);
my $message;
if ($response->is_success) {
	$message = $response->decoded_content;
#	print $message."\n";
}
else {
#	print $response->code."\n";
#	print $response->message."\n";
	$message = $response->code.$response->message;
}

    return $message;
}
