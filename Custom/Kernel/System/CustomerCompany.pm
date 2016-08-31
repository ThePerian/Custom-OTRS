# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::CustomerCompany;

use strict;
use warnings;

use base qw(Kernel::System::EventHandler);
use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
);

=head1 NAME

Kernel::System::CustomerCompany - customer company lib

=head1 SYNOPSIS

All Customer functions. E.g. to add and update customer companies.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $CustomerCompanyObject = $Kernel::OM->Get('Kernel::System::CustomerCompany');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get needed objects
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $MainObject   = $Kernel::OM->Get('Kernel::System::Main');

    # load customer company backend modules
    SOURCE:
    for my $Count ( '', 1 .. 10 ) {

        next SOURCE if !$ConfigObject->Get("CustomerCompany$Count");

        my $GenericModule = $ConfigObject->Get("CustomerCompany$Count")->{Module}
            || 'Kernel::System::CustomerCompany::DB';
        if ( !$MainObject->Require($GenericModule) ) {
            $MainObject->Die("Can't load backend module $GenericModule! $@");
        }
        $Self->{"CustomerCompany$Count"} = $GenericModule->new(
            Count              => $Count,
            CustomerCompanyMap => $ConfigObject->Get("CustomerCompany$Count"),
        );
    }

    # get the dynamic fields for this object
    $Self->{DynamicField} = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => [ 'CustomerCompany' ],
    );

    # init of event handler
    $Self->EventHandlerInit(
        Config => 'CustomerCompany::EventModulePost',
    );

    return $Self;
}

=item CustomerCompanyAdd()

add a new customer company

    my $ID = $CustomerCompanyObject->CustomerCompanyAdd(
        CustomerID              => '12345', 		#MUST be only numbers, otherwise Dynamic Fields won't work
        CustomerCompanyName     => 'New Customer Inc.',
        CustomerCompanyStreet   => '5201 Blue Lagoon Drive',
        CustomerCompanyZIP      => '33126',
        CustomerCompanyCity     => 'Miami',
        CustomerCompanyCountry  => 'USA',
        CustomerCompanyURL      => 'http://www.example.org',
        CustomerCompanyComment  => 'some comment',
        ValidID                 => 1,
        UserID                  => 123,

	#optional dynamic fields hash
	DynamicFields		=> {
	    DynamicFieldName	=> DynamicFieldValue,
	}
    );

NOTE: Actual fields accepted by this API call may differ based on
CustomerCompany mapping in your system configuration.

=cut

sub CustomerCompanyAdd {
    my ( $Self, %Param ) = @_;

    # check data source
    if ( !$Param{Source} ) {
        $Param{Source} = 'CustomerCompany';
    }

    # check needed stuff
    for (qw(CustomerID UserID)) {
        if ( !$Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    my $Result = $Self->{ $Param{Source} }->CustomerCompanyAdd(%Param);
    return if !$Result;

    # trigger event
    $Self->EventHandler(
        Event => 'CustomerCompanyAdd',
        Data  => {
            CustomerID => $Param{CustomerID},
            NewData    => \%Param,
        },
        UserID => $Param{UserID},
    );

    #set dynamic fields if any are given
    if (IsHashRefWithData($Param{DynamicFields})) {
	my $DynamicFields = $Param{DynamicFields};

	# get dynamic field objects
    	my $DynamicFieldObject        = $Kernel::OM->Get('Kernel::System::DynamicField');
    	my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');	

	#update all provided dynamic fields
	DYNAMICFIELD:
    	for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

	    my $DynamicFieldValue = $DynamicFields->{ $DynamicFieldConfig->{Name} } || '';

	    my $result = $DynamicFieldBackendObject->ValueSet(
            	DynamicFieldConfig => $DynamicFieldConfig,
            	ObjectID           => $Param{CustomerCompanyID}||$Param{CustomerID},
            	UserID             => $Param{UserID},
            	Value              => $DynamicFieldValue,
            );
	}
    }

################################################################################
#	edit to make http request after adding new company

# # 	use LWP::UserAgent;
	# use HTTP::Request::Common;
	# my $url = 'URL';
	# my %UserData = $Self->CustomerCompanyGet( 
		# CustomerID => $Param{CustomerCompanyID}||$Param{CustomerID},
		# DynamicFields => 1, 
	# );
	# my $content = "{\"CustomerCompany\":{";
	# while ( my ($key, $value) = each(%UserData)) {
		# $content .= "\"$key\":\"$value\",";
	# }
	# $content .= "}}";

# # 	my $ua       = LWP::UserAgent->new();
	# my $request  = HTTP::Request->new(POST => $url);
	# $request->header('content-type' => 'application/json');
	# $request->content($content);
	# my $response = $ua->request($request);
#	if ($response->is_success) {
#		print $response->decoded_content."\n";
#	}
#	else {
#		print $response->code."\n";
#		print $response->message."\n";
#	}
################################################################################

    return $Result;
}

=item CustomerCompanyGet()

get customer company attributes

    my %CustomerCompany = $CustomerCompanyObject->CustomerCompanyGet(
        CustomerID => 123,
        DynamicFields => 0, # Optional, default 0. To include the dynamic field values for this company on the return structure.
    );

Returns:

    %CustomerCompany = (
        'CustomerCompanyName'    => 'Customer Inc.',
        'CustomerID'             => '12345', 		#MUST be only numbers, otherwise Dynamic Fields won't work
        'CustomerCompanyStreet'  => '5201 Blue Lagoon Drive',
        'CustomerCompanyZIP'     => '33126',
        'CustomerCompanyCity'    => 'Miami',
        'CustomerCompanyCountry' => 'United States',
        'CustomerCompanyURL'     => 'http://example.com',
        'CustomerCompanyComment' => 'Some Comments',
        'ValidID'                => '1',
        'CreateTime'             => '2010-10-04 16:35:49',
        'ChangeTime'             => '2010-10-04 16:36:12',

	# If DynamicFields => 1 was passed, you'll get an entry like this for each dynamic field:
        DynamicField_X     => 'value_x',
    );

NOTE: Actual fields returned by this API call may differ based on
CustomerCompany mapping in your system configuration.

=cut

sub CustomerCompanyGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{CustomerID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need CustomerID!"
        );
        return;
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    SOURCE:
    for my $Count ( '', 1 .. 10 ) {

        next SOURCE if !$Self->{"CustomerCompany$Count"};

        my %Company = $Self->{"CustomerCompany$Count"}->CustomerCompanyGet( %Param, );
        next SOURCE if !%Company;

	#get dynamic fields if needed	
	my $FetchDynamicFields = $Param{DynamicFields} ? 1 : 0;
	
	if ($FetchDynamicFields) {

	    # get dynamic field objects
	    my $DynamicFieldObject        = $Kernel::OM->Get('Kernel::System::DynamicField');
	    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

	    # get all dynamic fields for the object type CustomerCompany
	    my $DynamicFieldList = $DynamicFieldObject->DynamicFieldListGet(
	    	ObjectType => 'CustomerCompany'
	    );

	    DYNAMICFIELD:
	    for my $DynamicFieldConfig ( @{$DynamicFieldList} ) {

	    	# validate each dynamic field
	    	next DYNAMICFIELD if !$DynamicFieldConfig;
	    	next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);
	    	next DYNAMICFIELD if !$DynamicFieldConfig->{Name};

	    	# get the current value for each dynamic field
	    	my $Value = $DynamicFieldBackendObject->ValueGet(
	            DynamicFieldConfig => $DynamicFieldConfig,
	            ObjectID           => $Param{CustomerCompanyID}||$Param{CustomerID},
	    	);

	    	# set the dynamic field name and value into the customer company hash
	    	$Company{ 'DynamicField_' . $DynamicFieldConfig->{Name} } = $Value;
	    }
    	}

        # return company data
        return (
            %Company,
            Source => "CustomerCompany$Count",
            Config => $ConfigObject->Get("CustomerCompany$Count"),
        );
    }

    return;
}

=item CustomerCompanyUpdate()

update customer company attributes

    $CustomerCompanyObject->CustomerCompanyUpdate(
        CustomerCompanyID       => 'oldexample.com', # required for CustomerCompanyID-update
        CustomerID              => '12345', 		#MUST be only numbers, otherwise Dynamic Fields won't work
        CustomerCompanyName     => 'New Customer Inc.',
        CustomerCompanyStreet   => '5201 Blue Lagoon Drive',
        CustomerCompanyZIP      => '33126',
        CustomerCompanyLocation => 'Miami',
        CustomerCompanyCountry  => 'USA',
        CustomerCompanyURL      => 'http://example.com',
        CustomerCompanyComment  => 'some comment',
        ValidID                 => 1,
        UserID                  => 123,

	#optional dynamic fields hash
	DynamicFields		=> {
	    DynamicFieldName	=> DynamicFieldValue,
	}
    );

=cut

sub CustomerCompanyUpdate {
    my ( $Self, %Param ) = @_;

    $Param{CustomerCompanyID} ||= $Param{CustomerID};

    # check needed stuff
    if ( !$Param{CustomerCompanyID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need CustomerCompanyID or CustomerID!"
        );
        return;
    }

    # check if company exists
    my %Company = $Self->CustomerCompanyGet( CustomerID => $Param{CustomerCompanyID} );
    if ( !%Company ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "No such company '$Param{CustomerCompanyID}'!",
        );
        return;
    }
    my $Result = $Self->{ $Company{Source} }->CustomerCompanyUpdate(%Param);
    return if !$Result;

    # trigger event
    $Self->EventHandler(
        Event => 'CustomerCompanyUpdate',
        Data  => {
            CustomerID    => $Param{CustomerID},
            OldCustomerID => $Param{CustomerCompanyID},
            NewData       => \%Param,
            OldData       => \%Company,
        },
        UserID => $Param{UserID},
    );

    #set dynamic fields if any are given
    if (IsHashRefWithData($Param{DynamicFields})) {
	my $DynamicFields = $Param{DynamicFields};

	# get dynamic field objects
    	my $DynamicFieldObject        = $Kernel::OM->Get('Kernel::System::DynamicField');
    	my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');	

	#update all provided dynamic fields
	while( my ($DynamicFieldName, $DynamicFieldValue) = each(%{$DynamicFields})) {

	    my $DynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
            	Name => $DynamicFieldName,
            );

	    if ( !$DynamicFieldConfig ) {
            	$Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'Error',
                    Message  => qq[No such dynamic field "$DynamicFieldName"],
            	);
                return;
            }

	    $DynamicFieldBackendObject->ValueSet(
            	DynamicFieldConfig => $DynamicFieldConfig,
            	ObjectID           => $Param{CustomerCompanyID},
            	UserID             => $Param{UserID},
            	Value              => $DynamicFieldValue,
            );
	}
    }
################################################################################
#	edit to make http request after updating a company

# # 	use LWP::UserAgent;
	# use HTTP::Request::Common;
	# my $url = 'URL';
	# my %UserData = $Self->CustomerCompanyGet( 
		# CustomerID => $Param{CustomerCompanyID},
		# DynamicFields => 1, 
	# );
	# my $content = "{\"CustomerCompany\":{";
	# while ( my ($key, $value) = each(%UserData)) {
		# $content .= "\"$key\":\"$value\",";
	# }
	# $content .= "}}";

# # 	my $ua       = LWP::UserAgent->new();
	# my $request  = HTTP::Request->new(PATCH => $url);
	# $request->header('content-type' => 'application/json');
	# $request->content($content);
	# my $response = $ua->request($request);
#	if ($response->is_success) {
#		print $response->decoded_content."\n";
#	}
#	else {
#		print $response->code."\n";
#		print $response->message."\n";
#	}
################################################################################

    return $Result;
}

=item CustomerCompanySourceList()

return customer company source list

    my %List = $CustomerCompanyObject->CustomerCompanySourceList(
        ReadOnly => 0 # optional, 1 returns only RO backends, 0 returns writable, if not passed returns all backends
    );

=cut

sub CustomerCompanySourceList {
    my ( $Self, %Param ) = @_;

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my %Data;
    SOURCE:
    for my $Count ( '', 1 .. 10 ) {

        next SOURCE if !$ConfigObject->Get("CustomerCompany$Count");

        if ( defined $Param{ReadOnly} ) {
            my $BackendConfig = $ConfigObject->Get("CustomerCompany$Count");
            if ( $Param{ReadOnly} ) {
                next SOURCE if !$BackendConfig->{ReadOnly};
            }
            else {
                next SOURCE if $BackendConfig->{ReadOnly};
            }
        }

        $Data{"CustomerCompany$Count"} = $ConfigObject->Get("CustomerCompany$Count")->{Name}
            || "No Name $Count";
    }

    return %Data;
}

=item CustomerCompanyList()

get list of customer companies.

    my %List = $CustomerCompanyObject->CustomerCompanyList();

    my %List = $CustomerCompanyObject->CustomerCompanyList(
        Valid => 0,
        Limit => 0,     # optional, override configured search result limit (0 means unlimited)
    );

    my %List = $CustomerCompanyObject->CustomerCompanyList(
        Search => 'somecompany',
    );

Returns:

%List = {
          'example.com' => 'example.com Customer Inc.',
          'acme.com'    => 'acme.com Acme, Inc.'
        };

=cut

sub CustomerCompanyList {
    my ( $Self, %Param ) = @_;

    my %Data;
    SOURCE:
    for my $Count ( '', 1 .. 10 ) {

        next SOURCE if !$Self->{"CustomerCompany$Count"};

        # get comppany list result of backend and merge it
        my %SubData = $Self->{"CustomerCompany$Count"}->CustomerCompanyList(%Param);
        %Data = ( %Data, %SubData );
    }
    return %Data;
}

sub DESTROY {
    my $Self = shift;

    # execute all transaction events
    $Self->EventHandlerTransaction();

    return 1;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
