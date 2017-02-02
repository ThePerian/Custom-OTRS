# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::GenericInterface::Operation::Customer::CustomerUserMultiUpsert;

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

Kernel::GenericInterface::Operation::Customer::CustomerUserMultiUpsert - GenericInterface Customer CustomerUserMultiUpsert Operation backend

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

    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('GenericInterface::Operation::CustomerUserMultiUpsert');

    return $Self;
}

=item Run()

perform CustomerUserMultiUpsert Operation. This will return the created or updated user logins.

    my $Result = $OperationObject->Run(
        Data => {
            UserLogin         => 'some agent login',                            # UserLogin or SessionID is
                                                                                #   required
            SessionID         => 123,

            Password  => 'some password',                                       # if UserLogin is sent then
                                                                                #   Password is required

            CustomerUserData => [
                {                                                               # first customer user info
                    Source         => 'CustomerUser',
                    UserLogin      => 'new login',
                    ID             => 'old login'
                    UserFirstname  => 'first-name',
                    UserLastname   => 'last-name',
                    UserCustomerID => 'customer-id',
                    UserPassword   => 'password',
                    UserEmail      => 'email-address',
                    ValidID        => 1,
                },
                {                                                               # second customer user info
                    ...
                },
                ...
            ]
        },
    );

    $Result = {
        Success         => 1,                       # 0 or 1
        ErrorMessage    => '',                      # in case of error
        Data            => {                        # result data payload after Operation
           Result    => [user logins],              # Customer user logins in OTRS (help desk system)
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
            ErrorCode    => 'CustomerUserMultiUpsert.MissingParameter',
            ErrorMessage => "CustomerUserMultiUpsert: UserLogin or SessionID is required!",
        );
    }

    if ( $Param{Data}->{UserLogin} ) {

        if ( !$Param{Data}->{Password} )
        {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerUserMultiUpsert.MissingParameter',
                ErrorMessage => "CustomerUserMultiUpsert: Password or SessionID is required!",
            );
        }
    }

    # authenticate user
    my ( $UserID, $UserType ) = $Self->Auth(
        %Param,
    );

    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerUserMultiUpsert.AuthFail',
            ErrorMessage => "CustomerUserMultiUpsert: User could not be authenticated!",
        );
    }

    # check needed hashes
    for my $Needed ( 'CustomerUserData' ) {
        if ( !IsArrayRefWithData( $Param{Data}->{$Needed} ) ) {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerUserMultiUpsert.MissingParameter',
                ErrorMessage => "CustomerUserMultiUpsert: $Needed parameter is missing or not valid!",
            );
        }
    }

    # isolate customer user parameter
    my $CustomerUserData = $Param{Data}->{CustomerUserData};
    my @NewCustomerUserData;

    # remove leading and trailing spaces
    for my $CustomerUser ( @{$CustomerUserData} ) {
        if ( !IsHashRefWithData( $CustomerUser ) ) {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerUserMultiUpsert.MissingParameter',
                ErrorMessage => "CustomerUserMultiUpsert: CustomerUser data is missing or not valid!",
            );
        }
        for my $Attribute ( sort keys %{$CustomerUser} ) {
            if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

                #remove leading spaces
                $CustomerUser->{$Attribute} =~ s{\A\s+}{};

                #remove trailing spaces
                $CustomerUser->{$Attribute} =~ s{\s+\z}{};
            }
        }
        
        push @NewCustomerUserData, $CustomerUser;
    }

    return $Self->_CustomerUserMultiUpsert(
        CustomerUserData  => \@NewCustomerUserData,
        UserID            => $UserID,
    );
}

=begin Internal:

=item _CustomerUserMultiUpsert()

creates a customer user with specified parameters

    my $Response = $OperationObject->_CustomerUserMultiUpsert(
        CustomerUserData => [
            CustomerUser1 => {
                Source         => 'CustomerUser',
                UserLogin      => $Self->GetOption('new login'),
                ID             => $Self->GetOption('old login'),
                UserFirstname  => $Self->GetOption('first-name'),
                UserLastname   => $Self->GetOption('last-name'),
                UserCustomerID => $Self->GetOption('customer-id'),
                UserPassword   => $Self->GetOption('password'),
                UserEmail      => $Self->GetOption('email-address'),
                ValidID        => 1,
            },
            CustomerUser2 => {
                ...
            },
            ...
        ],
        UserID                  => 'UserID',
    );

    returns:

    $Response = {
        Success => 1,                               # if everything is OK
        Data => {
            Result     => [user logins],
        }
    }

    $Response = {
        Success      => 0,                         # if unexpected error
        ErrorMessage => "$Param{ErrorCode}: $Param{ErrorMessage}",
    }

=cut

sub _CustomerUserMultiUpsert {
    my ( $Self, %Param ) = @_;

    my $CustomerUserData  = $Param{CustomerUserData};

    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');
	
    my @CustomerUsers;

    for my $CustomerUser ( @{$CustomerUserData} ) {
        # save old value of CustomerUser in case of update
        my %CustomerUserOld = $CustomerUserObject->CustomerUserDataGet(
            User => $CustomerUser->{ID} || $CustomerUser->{UserLogin}
        );
        
        if (%CustomerUserOld) {
            my $UserEmail;
            if (index($CustomerUser->{UserEmail}, '@noemail.ru', 0) != -1) {
                $UserEmail = $CustomerUserOld{UserEmail};
            }
            else {
                $UserEmail = $CustomerUser->{UserEmail};
            }
            my $Result = $CustomerUserObject->CustomerUserUpdate(
                    Source         => $CustomerUser->{Source} || 'CustomerUser',
                    UserCustomerID => $CustomerUser->{UserCustomerID},
                    ID             => $CustomerUser->{ID},
                    UserLogin      => $CustomerUser->{UserLogin},
                    UserFirstname  => $CustomerUser->{UserFirstname} || $CustomerUserOld{UserFirstname},
                    UserLastname   => $CustomerUser->{UserLastname} || $CustomerUserOld{UserLastname},
                    UserPassword   => $CustomerUser->{UserPassword} || $CustomerUserOld{UserPassword},
                    UserEmail      => $UserEmail,
                    ValidID        => $CustomerUser->{ValidID} || 1,
                    UserID         => $Param{UserID},
                );

            if ( !$Result ) {
                return {
                    Success      => 0,
                    ErrorMessage => 'Customer user could not be updated, please contact the system administrator',
                };
            }
            
            push @CustomerUsers, $CustomerUser->{UserLogin};
        }
        else {
            my $CustomerUserLogin = $CustomerUserObject->CustomerUserAdd(
                    Source         => $CustomerUser->{Source} || 'CustomerUser',
                    UserLogin      => $CustomerUser->{UserLogin},
                    UserFirstname  => $CustomerUser->{UserFirstname},
                    UserLastname   => $CustomerUser->{UserLastname},
                    UserCustomerID => $CustomerUser->{UserCustomerID},
                    UserPassword   => $CustomerUser->{UserPassword} || '',
                    UserEmail      => $CustomerUser->{UserEmail},
                    ValidID        => $CustomerUser->{ValidID} || 1,
                    UserID         => $Param{UserID},
                );

            if ( !$CustomerUserLogin ) {
                return {
                    Success      => 0,
                    ErrorMessage => 'Customer user could not be created, please contact the system administrator',
                };
            }
            
            push @CustomerUsers, $CustomerUserLogin;
        }
    }
    
    return {
        Success => 1,
        Data    => {
            Result => \@CustomerUsers,
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
