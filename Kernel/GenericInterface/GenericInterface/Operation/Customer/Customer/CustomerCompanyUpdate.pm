# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::GenericInterface::Operation::Customer::CustomerCompanyUpdate;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(IsArrayRefWithData IsHashRefWithData IsStringWithData);
use Kernel::System::ObjectManager;

use base qw(
    Kernel::GenericInterface::Operation::Common
    Kernel::GenericInterface::Operation::Customer::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::GenericInterface::Operation::Customer::CustomerCompanyUpdate - GenericInterface CustomerCompany CustomerCompanyUpdate Operation backend

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

usually, you want to create an instance of this
by using Kernel::GenericInterface::Operation->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw( DebuggerObject WebserviceID )) {
        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!"
            };
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('GenericInterface::Operation::CustomerCompanyUpdate');

    return $Self;
}

=item Run()

perform CustomerCompanyUpdate Operation. This will return the updated company ID.

    my $Result = $OperationObject->Run(
        Data => {
            UserLogin         => 'some agent login',                            # UserLogin or SessionID is
                                                                                #   required
            SessionID         => 123,

            Password  => 'some password',                                       # if UserLogin is sent then
                                                                                #   Password is required

            CustomerCompany => {
		CustomerCompanyID		=> 'old ID',			# required, MUST be only numbers, otherwise Dynamic Fields won't work
                CustomerID      		=> 'new ID',			# required, can be same as old
		CustomerCompanyName		=> 'some name',			# required
		CustomerCompanyStreet		=> 'some street',		# optional
		CustomerCompanyZIP		=> '123456',			# optional
		CustomerCompanyLocarion		=> 'some location',		# optional
		CustomerCompanyCity		=> 'some city',			# optional
		CustomerCompanyCountry		=> 'some country',		# optional
		CustomerCompanyURL		=> 'example.com',		# optional
		CustomerCompanyComment		=> 'some comment',		# optional
		ValidID				=> '1',				# required, 1 or 0
	    },
        },
    );

    $Result = {
        Success         => 1,                       # 0 or 1
        ErrorMessage    => '',                      # in case of error
        Data            => {                        # result data payload after Operation
           CustomerID    	=> 'some ID',       # Company ID number in OTRS (help desk system)
            CustomerCompanyName => 'some name',     # Company name in OTRS (Help desk system)
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    my $Result = $Self->Init(
        WebserviceID => $Self->{WebserviceID},
    );

    if ( !$Result->{Success} ) {
        $Self->ReturnError(
            ErrorCode    => 'Webservice.InvalidConfiguration',
            ErrorMessage => $Result->{ErrorMessage},
        );
    }

    # check needed stuff
    if (
        !$Param{Data}->{UserLogin}
        && !$Param{Data}->{SessionID}
        )
    {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerCompanyUpdate.MissingParameter',
            ErrorMessage => "CustomerCompanyUpdate: UserLogin or SessionID is required!",
        );
    }

    if ( $Param{Data}->{UserLogin} ) {

        if ( !$Param{Data}->{Password} )
        {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerCompanyUpdate.MissingParameter',
                ErrorMessage => "CustomerCompanyUpdate: Password or SessionID is required!",
            );
        }
    }

    # authenticate user
    my ( $UserID, $UserType ) = $Self->Auth(
        %Param,
    );

    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerUpdate.AuthFail',
            ErrorMessage => "CustomerUpdate: User could not be authenticated!",
        );
    }

    my $PermissionUserID = $UserID;
    if ( $UserType eq 'Customer' ) {
        $UserID = $Kernel::OM->Get('Kernel::Config')->Get('CustomerPanelUserID')
    }

    # check needed hashes
    for my $Needed ( 'CustomerCompany' ) {
        if ( !IsHashRefWithData( $Param{Data}->{$Needed} ) ) {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerCompanyUpdate.MissingParameter',
                ErrorMessage => "CustomerCompanyUpdate: $Needed parameter is missing or not valid!",
            );
        }
    }

    # isolate customer company parameter
    my $CustomerCompany = $Param{Data}->{CustomerCompany};

    # remove leading and trailing spaces
    for my $Attribute ( sort keys %{$CustomerCompany} ) {
        if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

            #remove leading spaces
            $CustomerCompany->{$Attribute} =~ s{\A\s+}{};

            #remove trailing spaces
            $CustomerCompany->{$Attribute} =~ s{\s+\z}{};
        }
    }
    if ( IsHashRefWithData( $CustomerCompany->{PendingTime} ) ) {
        for my $Attribute ( sort keys %{ $CustomerCompany->{PendingTime} } ) {
            if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

                #remove leading spaces
                $CustomerCompany->{PendingTime}->{$Attribute} =~ s{\A\s+}{};

                #remove trailing spaces
                $CustomerCompany->{PendingTime}->{$Attribute} =~ s{\s+\z}{};
            }
        }
    }

    return $Self->_CustomerCompanyUpdate(
        CustomerCompany  => $CustomerCompany,
        UserID           => $UserID,
    );
}

=begin Internal:

=item _CustomerCompanyUpdate()

creates a customer company with specified parameters

    my $Response = $OperationObject->_CustomerCompanyCreate(
	CustomerCompanyID	=> 'OldCustomerID', 		#MUST be only numbers, otherwise Dynamic Fields won't work
        CustomerID              => 'CustomerID',
        CustomerCompanyName     => 'CustomerCompanyName',
        CustomerCompanyStreet   => 'CustomerCompanyStreet',
        CustomerCompanyZIP      => 'CustomerCompanyZIP',
	CustomerCompanyLocation	=> 'CustomerCompanyLocaion',
        CustomerCompanyCity     => 'CustomerCompanyCity',
        CustomerCompanyCountry  => 'CustomerCompanyCountry',
        CustomerCompanyURL      => 'CustomerCompanyURL',
        CustomerCompanyComment  => 'CustomerCompanyComment',
        ValidID                 => 1,
        UserID                  => 'UserID',
    );

    returns:

    $Response = {
        Success => 1,                               # if everething is OK
        Data => {
            CustomerID     => 123,
            CustomerCompanyName => 'name',
        }
    }

    $Response = {
        Success      => 0,                         # if unexpected error
        ErrorMessage => "$Param{ErrorCode}: $Param{ErrorMessage}",
    }

=cut

sub _CustomerCompanyUpdate {
    my ( $Self, %Param ) = @_;

    my $CustomerCompany  = $Param{CustomerCompany};

	local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $CustomerCompanyObject = $Kernel::OM->Get('Kernel::System::CustomerCompany');
	my %CustomerCompanyOld = $CustomerCompanyObject->CustomerCompanyGet(
		CustomerID => $CustomerCompany->{CustomerCompanyID}
	);

	my $Result = $CustomerCompanyObject->CustomerCompanyUpdate(
	CustomerCompanyID	=> $CustomerCompany->{CustomerCompanyID},
        CustomerID              => $CustomerCompany->{CustomerID},
        CustomerCompanyName     => $CustomerCompany->{CustomerCompanyName},
        CustomerCompanyStreet   => $CustomerCompany->{CustomerCompanyStreet} || $CustomerCompanyOld{CustomerCompanyStreet},
        CustomerCompanyZIP      => $CustomerCompany->{CustomerCompanyZIP} || $CustomerCompanyOld{CustomerCompanyZIP},
	CustomerCompanyLocation => $CustomerCompany->{CustomerCompanyLocation} || $CustomerCompanyOld{CustomerCompanyLocation},
        CustomerCompanyCity     => $CustomerCompany->{CustomerCompanyCity} || $CustomerCompanyOld{CustomerCompanyCity},
        CustomerCompanyCountry  => $CustomerCompany->{CustomerCompanyCountry} || $CustomerCompanyOld{CustomerCompanyCountry},
        CustomerCompanyURL      => $CustomerCompany->{CustomerCompanyURL} || $CustomerCompanyOld{CustomerCompanyURL},
        CustomerCompanyComment  => $CustomerCompany->{CustomerCompanyComment} || $CustomerCompanyOld{CustomerCompanyComment},
        ValidID                 => $CustomerCompany->{ValidID} || 1,
        UserID                  => $Param{UserID},
	DynamicFields		=> \%{$CustomerCompany->{DynamicFields}},
    );

    if ( !$Result ) {
        return {
            Success      => 0,
            ErrorMessage => 'Customer company could not be updated, please contact the system administrator',
        };
    }

    return {
        Success => 1,
        Data    => {
            Result => $Result,
        },
    };
}

1;

=end Internal:

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
