# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::GenericInterface::Operation::Customer::CustomerUserUpdate;

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

Kernel::GenericInterface::Operation::Customer::CustomerUserUpdate - GenericInterface Customer CustomerUserUpdate Operation backend

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

    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('GenericInterface::Operation::CustomerUserUpdate');

    return $Self;
}

=item Run()

perform CustomerUserUpdate Operation. This will return the updated user login.

    my $Result = $OperationObject->Run(
        Data => {
            UserLogin         => 'some agent login',                            # UserLogin or SessionID is
                                                                                #   required
            SessionID         => 123,

            Password  => 'some password',                                       # if UserLogin is sent then
                                                                                #   Password is required

            CustomerUser => {
            	Source         => 'CustomerUser',
                UserCustomerID => 'CustomerID',
                ID             => 'old login'
            	UserLogin      => 'new login',
            	UserFirstname  => 'first-name',
            	UserLastname   => 'last-name',
            	UserPassword   => 'password',
            	UserEmail      => 'email-address',
            	ValidID        => 1,
            }
        },
    );

    $Result = {
        Success         => 1,                       # 0 or 1
        ErrorMessage    => '',                      # in case of error
        Data            => {                        # result data payload after Operation
           UserLogin    => 'some login',       # Customer user login in OTRS (help desk system)
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
            ErrorCode    => 'CustomerUserUpdate.MissingParameter',
            ErrorMessage => "CustomerUserUpdate: UserLogin or SessionID is required!",
        );
    }

    if ( $Param{Data}->{UserLogin} ) {

        if ( !$Param{Data}->{Password} )
        {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerUserUpdate.MissingParameter',
                ErrorMessage => "CustomerUserUpdate: Password or SessionID is required!",
            );
        }
    }

    # authenticate user
    my ( $UserID, $UserType ) = $Self->Auth(
        %Param,
    );

    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerUserUpdate.AuthFail',
            ErrorMessage => "CustomerUserUpdate: User could not be authenticated!",
        );
    }

    my $PermissionUserID = $UserID;
    if ( $UserType eq 'Customer' ) {
        $UserID = $Kernel::OM->Get('Kernel::Config')->Get('CustomerPanelUserID')
    }

    # check needed hashes
    for my $Needed ( 'CustomerUser' ) {
        if ( !IsHashRefWithData( $Param{Data}->{$Needed} ) ) {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerUserUpdate.MissingParameter',
                ErrorMessage => "CustomerUserUpdate: $Needed parameter is missing or not valid!",
            );
        }
    }

    # isolate customer user parameter
    my $CustomerUser = $Param{Data}->{CustomerUser};

    # remove leading and trailing spaces
    for my $Attribute ( sort keys %{$CustomerUser} ) {
        if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

            #remove leading spaces
            $CustomerUser->{$Attribute} =~ s{\A\s+}{};

            #remove trailing spaces
            $CustomerUser->{$Attribute} =~ s{\s+\z}{};
        }
    }
    if ( IsHashRefWithData( $CustomerUser->{PendingTime} ) ) {
        for my $Attribute ( sort keys %{ $CustomerUser->{PendingTime} } ) {
            if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

                #remove leading spaces
                $CustomerUser->{PendingTime}->{$Attribute} =~ s{\A\s+}{};

                #remove trailing spaces
                $CustomerUser->{PendingTime}->{$Attribute} =~ s{\s+\z}{};
            }
        }
    }

    return $Self->_CustomerUserUpdate(
        CustomerUser  => $CustomerUser,
        UserID           => $UserID,
    );
}

=begin Internal:

=item _CustomerUserUpdate()

updates a customer user with specified parameters

    my $Response = $OperationObject->_CustomerUserCreate(
        CustomerUser => {
            Source         => 'CustomerUser',
	    UserCustomerID => $Self->GetOption('CustomerID'),
	    ID		   => $Self->GetOption('old id'),
            UserLogin      => $Self->GetOption('new id'),
            UserFirstname  => $Self->GetOption('first-name'),
            UserLastname   => $Self->GetOption('last-name'),
            UserPassword   => $Self->GetOption('password'),
            UserEmail      => $Self->GetOption('email-address'),
            ValidID        => 1,
        }
        UserID                  => 'UserID',
    );

    returns:

    $Response = {
        Success => 1,                               # if everything is OK
        Data => {
            CustomerUserLogin     => 'some login',
        }
    }

    $Response = {
        Success      => 0,                         # if unexpected error
        ErrorMessage => "$Param{ErrorCode}: $Param{ErrorMessage}",
    }

=cut

sub _CustomerUserUpdate {
    my ( $Self, %Param ) = @_;

    my $CustomerUser  = $Param{CustomerUser};

    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');

    my %CustomerUserOld = $CustomerUserObject->CustomerUserDataGet(
	User => $CustomerUser->{UserLogin}
    );

    my $Result = $CustomerUserObject->CustomerUserUpdate(
            Source         => $CustomerUser->{Source} || 'CustomerUser',
	    UserCustomerID => $CustomerUser->{UserCustomerID},
	    ID		   => $CustomerUser->{ID},
            UserLogin      => $CustomerUser->{UserLogin},
            UserFirstname  => $CustomerUser->{UserFirstname} || $CustomerUserOld{UserFirstname},
            UserLastname   => $CustomerUser->{UserLastname} || $CustomerUserOld{UserLastname},
            UserPassword   => $CustomerUser->{UserPassword} || $CustomerUserOld{UserPassword},
            UserEmail      => $CustomerUser->{UserEmail} || $CustomerUserOld{UserEmail},
            ValidID        => $CustomerUser->{ValidID} || 1,
            UserID         => $Param{UserID},
        );

    if ( !$Result ) {
        return {
            Success      => 0,
            ErrorMessage => 'Customer user could not be updated, please contact the system administrator',
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
