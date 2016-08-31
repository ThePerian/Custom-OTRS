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

Kernel::GenericInterface::Operation::Customer::CustomerCompanyUpdate - GenericInterface Customer CustomerCompanyUpdate Operation backend

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

    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('GenericInterface::Operation::TicketUpdate');

    return $Self;
}

=item Run()

perform CustomerCompanyUpdate Operation. This will return the updated CustomerCompanyID.

    my $Result = $OperationObject->Run(
        Data => {
            UserLogin         => 'some agent login',                            # UserLogin or SessionID is
                                                                                #   required
            SessionID         => 123,

            Password  => 'some password',                                       # if UserLogin or customerUserLogin is sent then
                                                                                #   Password is required

            CustomerCompanyID     => 123,                                                # CustomerCompanyID is required

            CustomerCompany {                                                            
                CustomerCompanyID	=> 'old ID',		#required
		CustomerID		=> 'new ID',		#required
		CustomerCompanyName	=> 'Name',		#required
		CustomerCompanyStreet	=> 'Street',
		CustomerCompanyZIP	=> '123456',
		CustomerCompanyLocation	=> 'Location',
		CustomerCompanyCountry	=> 'Country',
		CustomerCompanyURL	=> 'example.com',
		CustomerCompanyComment	=> 'Comment',
		ValidID			=> 1 || 0, 		#required
            },
        },
    );

    $Result = {
        Success         => 1,                       # 0 or 1
        ErrorMessage    => '',                      # in case of error
        Data            => {                        # result data payload after Operation
            CustomerCompanyID    => 123,            # Customer company ID in OTRS (help desk system)
            Error => {                              # should not return errors
                    ErrorCode    => 'CustomerCompanyUpdate.ErrorCode'
                    ErrorMessage => 'Error Description'
            },
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
    if ( !IsHashRefWithData( $Param{Data} ) ) {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerCompanyUpdate.EmptyRequest',
            ErrorMessage => "CustomerCompanyUpdate: The request data is invalid!",
        );
    }

    if ( !$Param{Data}->{CustomerCompanyID}) {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerCompanyUpdate.MissingParameter',
            ErrorMessage => "CustomerCompanyUpdate: CustomerCompanyID is required!",
        );
    }

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

    if ( $Param{Data}->{UserLogin}) {

        if ( !$Param{Data}->{Password} )
        {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerCompanyUpdate.MissingParameter',
                ErrorMessage => "CustomerCompanyUpdate: Password or SessionID is required!",
            );
        }
    }

    # authenticate user
    my ( $UserID, $UserType ) = $Self->Auth(%Param);

    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerCompanyUpdate.AuthFail',
            ErrorMessage => "CustomerCompanyUpdate: User could not be authenticated!",
        );
    }

    my $PermissionUserID = $UserID;

    # get customer company object
    my $CustomerCompanyObject = $Kernel::OM->Get('Kernel::System::CustomerCompany');

    # check CustomerCompanyID
    my $CustomerCompanyID;
    if ( $Param{Data}->{CustomerCompanyID} ) {
        $CustomerCompanyID = $CustomerCompanyObject->CustomerCompanyGet(
            CustomerID       => $Param{Data}->{CustomerCompanyID},
        )->{CustomerID};

    }
    else {
        $CustomerCompanyID = $Param{Data}->{CustomerCompanyID};
    }

    if ( !($CustomerCompanyID) ) {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerCompanyUpdate.AccessDenied',
            ErrorMessage => "CustomerCompanyUpdate: User does not have access to the company!",
        );
    }

    my %CustomerCompanyData = $CustomerCompanyObject->CustomerCompanyGet(
        CustomerID      => $CustomerID,
    );

    if ( !IsHashRefWithData( \%CustomerCompany ) ) {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerCompanyUpdate.AccessDenied',
            ErrorMessage => "CustomerCompanyUpdate: User does not have access to the company!",
        );
    }

    my $CustomerCompany;
    if ( defined $Param{Data}->{CustomerCompany} ) {

        # isolate customer company parameter
        $CustomerCompany = $Param{Data}->{CustomerCompany};

        $CustomerCompany->{UserID} = $UserID;

        # remove leading and trailing spaces
        for my $Attribute ( sort keys %{$CustomerCompany} ) {
            if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

                #remove leading spaces
                $CustomerCompany->{$Attribute} =~ s{\A\s+}{};

                #remove trailing spaces
                $CustomerCompany->{$Attribute} =~ s{\s+\z}{};
            }
        }
    }
   
    return $Self->_CustomerCompanyUpdate(
        CustomerCompanyID         => $CustomerCompanyID,
        CustomerCompany           => $CustomerCompany,
        UserID           => $UserID,
        UserType         => $UserType,
    );
}

=begin Internal:



=item _CustomerCompanyUpdate()

updates a customer company.

    my $Response = $OperationObject->_CustomerCompanyUpdate(
        CustomerCompanyID     => 123
        CustomerCompany       => $CustomerCompany,                  # all customer company parameters
        UserID       => 123,
        UserType     => 'Agent'
    );

    returns:

    $Response = {
        Success => 1,                               # if everything is OK
        Data => {
            CustomerCompanyID     => 123,
        }
    }

    $Response = {
        Success      => 0,                         # if unexpected error
        ErrorMessage => "$Param{ErrorCode}: $Param{ErrorMessage}",
    }

=cut

sub _CustomerCompanyUpdate {
    my ( $Self, %Param ) = @_;

    my $CustomerCompanyID         = $Param{CustomerCompanyID};
    my $CustomerCompany           = $Param{CustomerCompany};

    # get customer company object
    my $CustomerCompanyObject = $Kernel::OM->Get('Kernel::System::CustomerCompany');

    # get current customer company data
    my %CustomerCompanyData = $CustomerCompanyObject->CustomerCompanyGet(
        CustomerID      => $CustomerCompanyID,
    );

    # update customer company parameters
    # update CustomerCompany->Name
    if (
        defined $Ticket->{Title}
        && $Ticket->{Title} ne ''
        && $Ticket->{Title} ne $TicketData{Title}
        )
    {
        my $Success = $TicketObject->TicketTitleUpdate(
            Title    => $Ticket->{Title},
            TicketID => $TicketID,
            UserID   => $Param{UserID},
        );
        if ( !$Success ) {
            return {
                Success => 0,
                Errormessage =>
                    'Ticket title could not be updated, please contact system administrator!',
                }
        }
    }

    # update Ticket->Queue
    if ( $Ticket->{Queue} || $Ticket->{QueueID} ) {
        my $Success;
        if ( defined $Ticket->{Queue} && $Ticket->{Queue} ne $TicketData{Queue} ) {
            $Success = $TicketObject->TicketQueueSet(
                Queue    => $Ticket->{Queue},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        elsif ( defined $Ticket->{QueueID} && $Ticket->{QueueID} ne $TicketData{QueueID} ) {
            $Success = $TicketObject->TicketQueueSet(
                QueueID  => $Ticket->{QueueID},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        else {

            # data is the same as in ticket nothing to do
            $Success = 1;
        }

        if ( !$Success ) {
            return {
                Success => 0,
                ErrorMessage =>
                    'Ticket queue could not be updated, please contact system administrator!',
                }
        }
    }

    # update Ticket->Lock
    if ( $Ticket->{Lock} || $Ticket->{LockID} ) {
        my $Success;
        if ( defined $Ticket->{Lock} && $Ticket->{Lock} ne $TicketData{Lock} ) {
            $Success = $TicketObject->TicketLockSet(
                Lock     => $Ticket->{Lock},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        elsif ( defined $Ticket->{LockID} && $Ticket->{LockID} ne $TicketData{LockID} ) {
            $Success = $TicketObject->TicketLockSet(
                LockID   => $Ticket->{LockID},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        else {

            # data is the same as in ticket nothing to do
            $Success = 1;
        }

        if ( !$Success ) {
            return {
                Success => 0,
                Errormessage =>
                    'Ticket lock could not be updated, please contact system administrator!',
                }
        }
    }

    # update Ticket->Type
    if ( $Ticket->{Type} || $Ticket->{TypeID} ) {
        my $Success;
        if ( defined $Ticket->{Type} && $Ticket->{Type} ne $TicketData{Type} ) {
            $Success = $TicketObject->TicketTypeSet(
                Type     => $Ticket->{Type},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        elsif ( defined $Ticket->{TypeID} && $Ticket->{TypeID} ne $TicketData{TypeID} )
        {
            $Success = $TicketObject->TicketTypeSet(
                TypeID   => $Ticket->{TypeID},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        else {

            # data is the same as in ticket nothing to do
            $Success = 1;
        }

        if ( !$Success ) {
            return {
                Success => 0,
                Errormessage =>
                    'Ticket type could not be updated, please contact system administrator!',
                }
        }
    }

    # update Ticket>State
    # depending on the state, might require to unlock ticket or enables pending time set
    if ( $Ticket->{State} || $Ticket->{StateID} ) {

        # get State Data
        my %StateData;
        my $StateID;

        # get state object
        my $StateObject = $Kernel::OM->Get('Kernel::System::State');

        if ( $Ticket->{StateID} ) {
            $StateID = $Ticket->{StateID};
        }
        else {
            $StateID = $StateObject->StateLookup(
                State => $Ticket->{State},
            );
        }

        %StateData = $StateObject->StateGet(
            ID => $StateID,
        );

        # force unlock if state type is close
        if ( $StateData{TypeName} =~ /^close/i ) {

            # set lock
            $TicketObject->TicketLockSet(
                TicketID => $TicketID,
                Lock     => 'unlock',
                UserID   => $Param{UserID},
            );
        }

        # set pending time
        elsif ( $StateData{TypeName} =~ /^pending/i ) {

            # set pending time
            if ( defined $Ticket->{PendingTime} ) {
                my $Success = $TicketObject->TicketPendingTimeSet(
                    UserID   => $Param{UserID},
                    TicketID => $TicketID,
                    %{ $Ticket->{PendingTime} },
                );

                if ( !$Success ) {
                    return {
                        Success => 0,
                        Errormessage =>
                            'Ticket pendig time could not be updated, please contact system'
                            . ' administrator!',
                        }
                }
            }
            else {
                return $Self->ReturnError(
                    ErrorCode    => 'TicketUpdate.MissingParameter',
                    ErrorMessage => 'Can\'t set a ticket on a pending state without pendig time!'
                    )
            }
        }

        my $Success;
        if ( defined $Ticket->{State} && $Ticket->{State} ne $TicketData{State} ) {
            $Success = $TicketObject->TicketStateSet(
                State    => $Ticket->{State},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        elsif ( defined $Ticket->{StateID} && $Ticket->{StateID} ne $TicketData{StateID} )
        {
            $Success = $TicketObject->TicketStateSet(
                StateID  => $Ticket->{StateID},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        else {

            # data is the same as in ticket nothing to do
            $Success = 1;
        }

        if ( !$Success ) {
            return {
                Success => 0,
                Errormessage =>
                    'Ticket state could not be updated, please contact system administrator!',
                }
        }
    }

    # update Ticket->Service
    # this might reset SLA if current SLA is not available for the new service
    if ( $Ticket->{Service} || $Ticket->{ServiceID} ) {

        # check if ticket has a SLA assigned
        if ( $TicketData{SLAID} ) {

            # check if old SLA is still valid
            if (
                !$Self->ValidateSLA(
                    SLAID     => $TicketData{SLAID},
                    Service   => $Ticket->{Service} || '',
                    ServiceID => $Ticket->{ServiceID} || '',
                )
                )
            {

                # remove current SLA if is not compatible with new service
                my $Success = $TicketObject->TicketSLASet(
                    SLAID    => '',
                    TicketID => $TicketID,
                    UserID   => $Param{UserID},
                );
            }
        }

        my $Success;

        # prevent comparison errors on undefined values
        if ( !defined $TicketData{Service} ) {
            $TicketData{Service} = '';
        }
        if ( !defined $TicketData{ServiceID} ) {
            $TicketData{ServiceID} = '';
        }

        if ( defined $Ticket->{Service} && $Ticket->{Service} ne $TicketData{Service} ) {
            $Success = $TicketObject->TicketServiceSet(
                Service  => $Ticket->{Service},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        elsif ( defined $Ticket->{ServiceID} && $Ticket->{ServiceID} ne $TicketData{ServiceID} )
        {
            $Success = $TicketObject->TicketServiceSet(
                ServiceID => $Ticket->{ServiceID},
                TicketID  => $TicketID,
                UserID    => $Param{UserID},
            );
        }
        else {

            # data is the same as in ticket nothing to do
            $Success = 1;
        }

        if ( !$Success ) {
            return {
                Success => 0,
                Errormessage =>
                    'Ticket service could not be updated, please contact system administrator!',
                }
        }
    }

    # update Ticket->SLA
    if ( $Ticket->{SLA} || $Ticket->{SLAID} ) {
        my $Success;

        # prevent comparison errors on undefined values
        if ( !defined $TicketData{SLA} ) {
            $TicketData{SLA} = '';
        }
        if ( !defined $TicketData{SLAID} ) {
            $TicketData{SLAID} = '';
        }

        if ( defined $Ticket->{SLA} && $Ticket->{SLA} ne $TicketData{SLA} ) {
            $Success = $TicketObject->TicketSLASet(
                SLA      => $Ticket->{SLA},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        elsif ( defined $Ticket->{SLAID} && $Ticket->{SLAID} ne $TicketData{SLAID} )
        {
            $Success = $TicketObject->TicketSLASet(
                SLAID    => $Ticket->{SLAID},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        else {

            # data is the same as in ticket nothing to do
            $Success = 1;
        }

        if ( !$Success ) {
            return {
                Success => 0,
                Errormessage =>
                    'Ticket SLA could not be updated, please contact system administrator!',
                }
        }
    }

    # update Ticket->CustomerUser && Ticket->CustomerID
    if ( $Ticket->{CustomerUser} || $Ticket->{CustomerID} ) {

        # set values to empty if they are not defined
        $TicketData{CustomerUserID} = $TicketData{CustomerUserID} || '';
        $TicketData{CustomerID}     = $TicketData{CustomerID}     || '';
        $Ticket->{CustomerUser}     = $Ticket->{CustomerUser}     || '';
        $Ticket->{CustomerID}       = $Ticket->{CustomerID}       || '';

        my $Success;
        if (
            $Ticket->{CustomerUser} ne $TicketData{CustomerUserID}
            || $Ticket->{CustomerID} ne $TicketData{CustomerID}
            )
        {
            my $CustomerID = $CustomerUserData{UserCustomerID} || '';

            # use user defined CustomerID if defined
            if ( defined $Ticket->{CustomerID} && $Ticket->{CustomerID} ne '' ) {
                $CustomerID = $Ticket->{CustomerID};
            }

            $Success = $TicketObject->TicketCustomerSet(
                No       => $CustomerID,
                User     => $Ticket->{CustomerUser},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        else {

            # data is the same as in ticket nothing to do
            $Success = 1;
        }

        if ( !$Success ) {
            return {
                Success => 0,
                Errormessage =>
                    'Ticket customer user could not be updated, please contact system administrator!',
                }
        }
    }

    # update Ticket->Priority
    if ( $Ticket->{Priority} || $Ticket->{PriorityID} ) {
        my $Success;
        if ( defined $Ticket->{Priority} && $Ticket->{Priority} ne $TicketData{Priority} ) {
            $Success = $TicketObject->TicketPrioritySet(
                Priority => $Ticket->{Priority},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        elsif ( defined $Ticket->{PriorityID} && $Ticket->{PriorityID} ne $TicketData{PriorityID} )
        {
            $Success = $TicketObject->TicketPrioritySet(
                PriorityID => $Ticket->{PriorityID},
                TicketID   => $TicketID,
                UserID     => $Param{UserID},
            );
        }
        else {

            # data is the same as in ticket nothing to do
            $Success = 1;
        }

        if ( !$Success ) {
            return {
                Success => 0,
                Errormessage =>
                    'Ticket priority could not be updated, please contact system administrator!',
                }
        }
    }

    # update Ticket->Owner
    if ( $Ticket->{Owner} || $Ticket->{OwnerID} ) {
        my $Success;
        if ( defined $Ticket->{Owner} && $Ticket->{Owner} ne $TicketData{Owner} ) {
            $Success = $TicketObject->TicketOwnerSet(
                NewUser  => $Ticket->{Owner},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        elsif ( defined $Ticket->{OwnerID} && $Ticket->{OwnerID} ne $TicketData{OwnerID} )
        {
            $Success = $TicketObject->TicketOwnerSet(
                NewUserID => $Ticket->{OwnerID},
                TicketID  => $TicketID,
                UserID    => $Param{UserID},
            );
        }
        else {

            # data is the same as in ticket nothing to do
            $Success = 1;
        }

        if ( !$Success ) {
            return {
                Success => 0,
                Errormessage =>
                    'Ticket owner could not be updated, please contact system administrator!',
                }
        }
    }

    # update Ticket->Responsible
    if ( $Ticket->{Responsible} || $Ticket->{ResponsibleID} ) {
        my $Success;
        if (
            defined $Ticket->{Responsible}
            && $Ticket->{Responsible} ne $TicketData{Responsible}
            )
        {
            $Success = $TicketObject->TicketResponsibleSet(
                NewUser  => $Ticket->{Responsible},
                TicketID => $TicketID,
                UserID   => $Param{UserID},
            );
        }
        elsif (
            defined $Ticket->{ResponsibleID}
            && $Ticket->{ResponsibleID} ne $TicketData{ResponsibleID}
            )
        {
            $Success = $TicketObject->TicketResponsibleSet(
                NewUserID => $Ticket->{ResponsibleID},
                TicketID  => $TicketID,
                UserID    => $Param{UserID},
            );
        }
        else {

            # data is the same as in ticket nothing to do
            $Success = 1;
        }

        if ( !$Success ) {
            return {
                Success => 0,
                Errormessage =>
                    'Ticket responsible could not be updated, please contact system administrator!',
                }
        }
    }

    if ($ArticleID) {
        return {
            Success => 1,
            Data    => {
                TicketID     => $TicketID,
                TicketNumber => $TicketData{TicketNumber},
                ArticleID    => $ArticleID,
            },
        };
    }
    return {
        Success => 1,
        Data    => {
            TicketID     => $TicketID,
            TicketNumber => $TicketData{TicketNumber},
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
