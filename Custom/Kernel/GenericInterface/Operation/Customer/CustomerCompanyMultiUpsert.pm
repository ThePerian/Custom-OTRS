# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::GenericInterface::Operation::Customer::CustomerCompanyMultiUpsert;

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

Kernel::GenericInterface::Operation::Customer::CustomerCompanyMultiUpsert - GenericInterface CustomerCompany CustomerCompanyMultiUpsert Operation backend

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

    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('GenericInterface::Operation::CustomerCompanyUpsert');

    return $Self;
}

=item Run()

perform CustomerCompanyMultiUpsert Operation. This will return the updated or created company IDs.

    my $Result = $OperationObject->Run(
        Data => {
            UserLogin         => 'some agent login',                            # UserLogin or SessionID is
                                                                                #   required
            SessionID         => 123,

            Password  => 'some password',                                       # if UserLogin is sent then
                                                                                #   Password is required

            CustomerCompanyData => [
                {                                                               # first customer company data
                    CustomerCompanyID		=> 'old ID',			# required, MUST be only numbers,
                                                                                # otherwise Dynamic Fields won't work
                    CustomerID      		=> 'new ID',			# required, can be same as old
                    CustomerCompanyName		=> 'some name',			# required
                    CustomerCompanyStreet	=> 'some street',	        # optional
                    CustomerCompanyZIP		=> '123456',			# optional
                    CustomerCompanyLocarion	=> 'some location',	        # optional
                    CustomerCompanyCity		=> 'some city',			# optional
                    CustomerCompanyCountry	=> 'some country',		# optional
                    CustomerCompanyURL		=> 'example.com',		# optional
                    CustomerCompanyComment	=> 'some comment',		# optional
                    ValidID			=> '1',				# required, 1 or 0; 1 by default
                    DynamicFields               => {                            # optional
                        DynamicFieldName1           => 'DynamicFieldValue1',
                        ...
                    },
                },
                {                                                               # second customer company data
                    ...
                },
                ...
            ]
        },
    );

    $Result = {
        Success         => 1,                       # 0 or 1
        ErrorMessage    => '',                      # in case of error
        Result            => [                      # result data payload after Operation
           {
               CustomerID    	    => 'some ID',   # Company ID number in OTRS (help desk system)
               CustomerCompanyName  => 'some name', # Company name in OTRS (Help desk system)
           },
           {
               ...
           },
        ],
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
            ErrorCode    => 'CustomerCompanyMultiUpsert.MissingParameter',
            ErrorMessage => "CustomerCompanyMultiUpsert: UserLogin or SessionID is required!",
        );
    }

    if ( $Param{Data}->{UserLogin} ) {

        if ( !$Param{Data}->{Password} )
        {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerCompanyMultiUpsert.MissingParameter',
                ErrorMessage => "CustomerCompanyMultiUpsert: Password or SessionID is required!",
            );
        }
    }

    # authenticate user
    my ( $UserID, $UserType ) = $Self->Auth(
        %Param,
    );

    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerCompanyUpsert.AuthFail',
            ErrorMessage => "CustomerCompanyUpsert: User could not be authenticated!",
        );
    }

    # check needed hashes
    for my $Needed ( 'CustomerCompanyData' ) {
        if ( !IsArrayRefWithData( $Param{Data}->{$Needed} ) ) {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerCompanyMultiUpsert.MissingParameter',
                ErrorMessage => "CustomerCompanyMultiUpsert: $Needed parameter is missing or not valid!",
            );
        }
    }

    # isolate customer company parameter
    my $CustomerCompanyData = $Param{Data}->{CustomerCompanyData};
    my @NewCustomerCompanyData;

    # remove leading and trailing spaces
    for my $CustomerCompany ( @{$CustomerCompanyData} ) {
        # check if CustomerCompany hash has needed parameters
        $Self->_CheckCustomerCompany(
            CustomerCompany  => $CustomerCompany,
        );
        
        if ( !IsHashRefWithData( $CustomerCompany ) ) {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerCompanyMultiUpsert.MissingParameter',
                ErrorMessage => "CustomerCompanyMultiUpsert: CustomerCompany data is missing or not valid!",
            );
        }
        for my $Attribute ( sort keys %{$CustomerCompany} ) {
            if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

                #remove leading spaces
                $CustomerCompany->{$Attribute} =~ s{\A\s+}{};

                #remove trailing spaces
                $CustomerCompany->{$Attribute} =~ s{\s+\z}{};
            }
        }
        if ( IsHashRefWithData( $CustomerCompany->{DynamicFields} ) ) {
            for my $Attribute ( sort keys %{ $CustomerCompany->{DynamicFields} } ) {
                if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

                    #remove leading spaces
                    $CustomerCompany->{DynamicFields}->{$Attribute} =~ s{\A\s+}{};

                    #remove trailing spaces
                    $CustomerCompany->{DynamicFields}->{$Attribute} =~ s{\s+\z}{};
                }
            }
        }
        
        push @NewCustomerCompanyData, $CustomerCompany;
    }

    return $Self->_CustomerCompanyMultiUpsert(
        CustomerCompanyData  => \@NewCustomerCompanyData,
        UserID               => $UserID,
    );
}

=begin Internal:

=item _CheckCustomerCompany()

checks if CustomerCompany hash is valid

    my $Response = $OperationObject->_CheckCustomerCompany(
        CustomerCompany => {
	    CustomerCompanyID		=> 'old ID',			# required, MUST be only numbers,
                                                                        # otherwise Dynamic Fields won't work
            CustomerID      		=> 'new ID',			# required, can be same as old
	    CustomerCompanyName		=> 'some name',			# required
	    CustomerCompanyStreet	=> 'some street',		# optional
	    CustomerCompanyZIP		=> '123456',			# optional
	    CustomerCompanyLocarion	=> 'some location',		# optional
	    CustomerCompanyCity		=> 'some city',			# optional
	    CustomerCompanyCountry	=> 'some country',		# optional
	    CustomerCompanyURL		=> 'example.com',		# optional
	    CustomerCompanyComment	=> 'some comment',		# optional
	    ValidID			=> '1',				# optional, 1 or 0; 1 by default
            DynamicFields               => {                            # optional
                DynamicFieldName1       => 'DynamicFieldValue1',
                ...
        },
    },

=cut

sub _CheckCustomerCompany() {
    my ( $Self, %Param ) = @_;

    my $CustomerCompany  = $Param{CustomerCompany};

    my $Success = 0;
    my $Message = 'OK';

    # check needed parameters
    for my $Needed (qw( CustomerCompanyID CustomerID CustomerCompanyName )) {
        if ( !( exists $CustomerCompany->{$Needed} ) ) {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerCompanyUpsert.MissingParameter',
                ErrorMessage => "CustomerCompanyUpsert: $Needed parameter is missing!",
            );
        }
        if ( !( defined $CustomerCompany->{$Needed} ) ) {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerCompanyUpsert.MissingParameter',
                ErrorMessage => "CustomerCompanyUpsert: $Needed parameter is undefined!",
            );
        }
    }

    # ids must consist of only numbers
    for my $ID (qw( CustomerCompanyID CustomerID )) {
        if ( $CustomerCompany->{$ID} !~ /\d/ ) {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerCompanyUpsert.InvalidParameter',
                ErrorMessage => "CustomerCompanyUpsert: $ID parameter must consist of only numbers!",
            );
        }
    }

    return;
}

=item _CustomerCompanyMultiUpsert()

creates, or updates a customer company with specified parameters

    my $Response = $OperationObject->_CustomerCompanyMultiUpsert(
        CustomerCompanyData             => [
            {                                                                   # first customer company info
                CustomerCompanyID		=> 'old ID',			# required, MUST be only numbers,
                                                                                # otherwise Dynamic Fields won't work
                CustomerID      		=> 'new ID',			# required, can be same as old
                CustomerCompanyName		=> 'some name',			# required
                CustomerCompanyStreet	        => 'some street',		# optional
                CustomerCompanyZIP		=> '123456',			# optional
                CustomerCompanyLocarion	        => 'some location',		# optional
                CustomerCompanyCity		=> 'some city',			# optional
                CustomerCompanyCountry	        => 'some country',		# optional
                CustomerCompanyURL		=> 'example.com',		# optional
                CustomerCompanyComment	        => 'some comment',		# optional
                ValidID			        => '1',				# optional, 1 or 0; 1 by default
                DynamicFields                   => {                            # optional
                    DynamicFieldName1       => 'DynamicFieldValue1',
                    ...
                }
            },
            {                                                                   # second customer company info
                ...
            },
            ...
        ]
        UserID                          => 'SomeID'
    );

    returns:

    $Response = {
        Success => 1,                                                   # if everething is OK
        Result => [
            {
                CustomerID             => 123,
                CustomerCompanyName    => 'CompanyName',
            },
            {
                ...
            },
            ...
        ]
    }

    $Response = {
        Success      => 0,                                              # if unexpected error
        ErrorMessage => "$Param{ErrorCode}: $Param{ErrorMessage}",
    }

=cut

sub _CustomerCompanyMultiUpsert {
    my ( $Self, %Param ) = @_;

    my $CustomerCompanyData  = $Param{CustomerCompanyData};

    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $CustomerCompanyObject = $Kernel::OM->Get('Kernel::System::CustomerCompany');
    
    my @CustomerCompanies;
    
    for my $CustomerCompany ( @{$CustomerCompanyData} ) {
        # save old value of CustomerCompany in case of update
        my %CustomerCompanyOld = $CustomerCompanyObject->CustomerCompanyGet(
            CustomerID => $CustomerCompany->{CustomerCompanyID}
        );
       
        if (%CustomerCompanyOld) {
            my $Result = $CustomerCompanyObject->CustomerCompanyUpdate(
                CustomerCompanyID	    => $CustomerCompany->{CustomerCompanyID},
                CustomerID              => $CustomerCompany->{CustomerID},
                CustomerCompanyName     => $CustomerCompany->{CustomerCompanyName},
                CustomerCompanyStreet   => $CustomerCompany->{CustomerCompanyStreet} 
                                           || $CustomerCompanyOld{CustomerCompanyStreet},
                CustomerCompanyZIP      => $CustomerCompany->{CustomerCompanyZIP} 
                                           || $CustomerCompanyOld{CustomerCompanyZIP},
                CustomerCompanyLocation => $CustomerCompany->{CustomerCompanyLocation} 
                                           || $CustomerCompanyOld{CustomerCompanyLocation},
                CustomerCompanyCity     => $CustomerCompany->{CustomerCompanyCity} 
                                           || $CustomerCompanyOld{CustomerCompanyCity},
                CustomerCompanyCountry  => $CustomerCompany->{CustomerCompanyCountry} 
                                           || $CustomerCompanyOld{CustomerCompanyCountry},
                CustomerCompanyURL      => $CustomerCompany->{CustomerCompanyURL} 
                                           || $CustomerCompanyOld{CustomerCompanyURL},
                CustomerCompanyComment  => $CustomerCompany->{CustomerCompanyComment} 
                                           || $CustomerCompanyOld{CustomerCompanyComment},
                ValidID                 => $CustomerCompany->{ValidID} 
                                           || $CustomerCompanyOld{ValidID},
                UserID                  => $Param{UserID},
                DynamicFields           => \%{$CustomerCompany->{DynamicFields}},
            );

            if ( !$Result ) {
                return {
                    Success      => 0,
                    ErrorMessage => 'Customer company could not be updated, please contact the system administrator',
                };
            }
            
            push @CustomerCompanies, {
                    CustomerID          => $CustomerCompany->{CustomerID},
                    CustomerCompanyName => $CustomerCompany->{CustomerCompanyName},
                };
        } 
        else {
            my $Result = $CustomerCompanyObject->CustomerCompanyAdd(
                CustomerID              => $CustomerCompany->{CustomerID},
                CustomerCompanyName     => $CustomerCompany->{CustomerCompanyName},
                CustomerCompanyStreet   => $CustomerCompany->{CustomerCompanyStreet} || '',
                CustomerCompanyZIP      => $CustomerCompany->{CustomerCompanyZIP} || '',
                CustomerCompanyLocation => $CustomerCompany->{CustomerCompanyLocation} || '',
                CustomerCompanyCity     => $CustomerCompany->{CustomerCompanyCity} || '',
                CustomerCompanyCountry  => $CustomerCompany->{CustomerCompanyCountry} || '',
                CustomerCompanyURL      => $CustomerCompany->{CustomerCompanyURL} || '',
                CustomerCompanyComment  => $CustomerCompany->{CustomerCompanyComment} || '',
                ValidID                 => $CustomerCompany->{ValidID} || 1,
                UserID                  => $Param{UserID},
                DynamicFields           => \%{$CustomerCompany->{DynamicFields}},
            );

            if ( !$Result ) {
                return {
                    Success      => 0,
                    ErrorMessage => 'Customer company could not be created, please contact the system administrator',
                };
            }

            # get customer company data
            my %CustomerCompanyResultData = $CustomerCompanyObject->CustomerCompanyGet(
                CustomerID => $Result,
            );

            if ( !IsHashRefWithData( \%CustomerCompanyResultData ) ) {
                return {
                    Success      => 0,
                    ErrorMessage => 'Could not get new customer company information, please contact the system'
                        . ' administrator',
                }
            }
            
            push @CustomerCompanies, {
                    CustomerID          => $Result,
                    CustomerCompanyName => $CustomerCompanyResultData{CustomerCompanyName},
                };
        }
    }
        
    return {
        Success => 1,
        Data    => {
            Result => \@CustomerCompanies,
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
