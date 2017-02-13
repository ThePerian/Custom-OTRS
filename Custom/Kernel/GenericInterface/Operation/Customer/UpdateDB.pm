# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::GenericInterface::Operation::Customer::UpdateDB;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(IsArrayRefWithData IsHashRefWithData IsStringWithData);
use Kernel::System::ObjectManager;
use XML::Simple;
use JSON qw( decode_json );

use base qw(
    Kernel::GenericInterface::Operation::Common
    Kernel::GenericInterface::Operation::Customer::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::GenericInterface::Operation::Customer::UpdateDB - GenericInterface Customer UpdateDB Operation backend

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

    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('GenericInterface::Operation::UpdateDB');

    return $Self;
}

=item Run()

perform UpdateDB Operation. This will return failed customer IDs.

    my $Result = $OperationObject->Run(
        Data => {
            UserLogin         => 'some agent login',      # UserLogin or SessionID is required
            SessionID         => 123,

            Password  => 'some password',                 # if UserLogin is sent then
                                                          # Password is required
                                                          
            XML => 'some XML string',                     # required, either XML string or 
                                                          # path to a local XML file
                                                          # containing updated DB content
            
            Fix => 1 or 0,                                # indicates if customer IDs that aren't
                                                          # in failed list should be skipped
        },
    );

    $Result = {
        Success         => 1,                       # 0 or 1
        ErrorMessage    => '',                      # in case of error
        Data            => {                        # result data payload after Operation
           Result    => [some IDs],                 # failed customer IDs as provided in XML
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
            ErrorCode    => 'UpdateDB.MissingParameter',
            ErrorMessage => "UpdateDB: UserLogin or SessionID is required!",
        );
    }

    if ( $Param{Data}->{UserLogin} ) {

        if ( !$Param{Data}->{Password} )
        {
            return $Self->ReturnError(
                ErrorCode    => 'UpdateDB.MissingParameter',
                ErrorMessage => "UpdateDB: Password or SessionID is required!",
            );
        }
    }

    # authenticate user
    my ( $UserID, $UserType ) = $Self->Auth(
        %Param,
    );

    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'UpdateDB.AuthFail',
            ErrorMessage => "UpdateDB: User could not be authenticated!",
        );
    }

    # check needed data
    for my $Needed ( 'XML' ) {
        if ( !$Param{Data}->{$Needed} ) {
            return $Self->ReturnError(
                ErrorCode    => 'UpdateDB.MissingParameter',
                ErrorMessage => "UpdateDB: $Needed parameter is missing or not valid!",
            );
        }
    }
    
    my $Fix = $Param{Data}->{Fix} || 0;

    # isolate XML parameter
    my $XML = $Param{Data}->{XML};

    return $Self->_UpdateDB(
        XML     => $XML,
        Fix     => $Fix,
        UserID  => $UserID,
    );
}

=begin Internal:

=item _UpdateDB()

updates DB with data from provided XML

    my $Response = $OperationObject->_UpdateDB(
        XML     => 'some XML string or path to local XML file',
        Fix     => 1 or 0,
        UserID  => 'UserID',
    );

    returns:

    $Response = {
        Success => 1,                               # if finished successfully
        Data    => {
            Result => [ ],                      # array of failed customer IDs
        }
    }

    $Response = {
        Success      => 0,                         # if unexpected error
        ErrorMessage => "$Param{ErrorCode}: $Param{ErrorMessage}",
    }

=cut

sub _UpdateDB {
    my ( $Self, %Param ) = @_;
    use Data::Dumper;
    use Encode qw(encode decode);

    my $XML = $Param{XML};

    open my $SystemCodesFile, '<', $Self->{Config}->{'SystemCodesLocation'};
    my $JString = do { local $/ = undef; <$SystemCodesFile> };
    my $SystemCodes = decode_json($JString);
    close $SystemCodesFile;
    
    unlink $Self->{Config}->{'ErrorLogLocation'};
    open my $ErrorLog, '>>', $Self->{Config}->{'ErrorLogLocation'};
    
    unlink $Self->{Config}->{'ErrorIDLocation'};
    open my $ErrorID, '>>', $Self->{Config}->{'ErrorIDLocation'};

    my $XMLData = XMLin( $XML, KeyAttr => [], ForceArray => 1);
    
    for my $Object ( @{$XMLData->{decode('UTF-8', 'Объект')}} ) {
        if ($Object->{decode('UTF-8', 'ИмяПравила')} eq "Clients") {
            
            my %CustomerCompanyData;
            
            for my $Param ( @{$Object->{decode('UTF-8', 'Свойство')}} ) {
                if ($Param->{decode('UTF-8', 'Имя')} eq 'id') {
                    $CustomerCompanyData{CustomerCompanyID} = $Param->{decode('UTF-8', 'Значение')};
                    $CustomerCompanyData{CustomerID} = $CustomerCompanyData{CustomerCompanyID};
                }
                elsif ($Param->{decode('UTF-8', 'Имя')} eq 'name') {
                    $CustomerCompanyData{CustomerCompanyName} = $Param->{decode('UTF-8', 'Значение')};
                }
                elsif ($Param->{decode('UTF-8', 'Имя')} eq 'title') {
                    $CustomerCompanyData{DynamicFields}{CustomerCompanyFullName} = $Param->{decode('UTF-8', 'Значение')};
                }
                elsif ($Param->{decode('UTF-8', 'Имя')} eq 'inn') {
                    $CustomerCompanyData{DynamicFields}{CustomerCompanyINN} = $Param->{decode('UTF-8', 'Значение')};
                }
                elsif ($Param->{decode('UTF-8', 'Имя')} eq 'verbose_title') {
                    $CustomerCompanyData{CustomerCompanyComment}  = $Param->{decode('UTF-8', 'Значение')};
                }
                elsif ($Param->{decode('UTF-8', 'Имя')} eq 'active') {
                    if ($Param->{decode('UTF-8', 'Значение')} eq 'true') {
                        $CustomerCompanyData{ValidID} = 1;
                    }
                    else {
                        $CustomerCompanyData{ValidID} = 0;
                    }
                }
            }
           
            # check if CustomerCompany hash has needed parameters
            $Self->_CheckCustomerCompany(
                CustomerCompany  => \%CustomerCompanyData,
            );

            # remove leading and trailing spaces
            for my $Attribute ( sort keys %CustomerCompanyData ) {
                if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

                    #remove leading spaces
                    $CustomerCompanyData{$Attribute} =~ s{\A\s+}{};

                    #remove trailing spaces
                    $CustomerCompanyData{$Attribute} =~ s{\s+\z}{};
                }
            }

            if ( IsHashRefWithData( $CustomerCompanyData{DynamicFields} ) ) {
                for my $Attribute ( sort keys %{ $CustomerCompanyData{DynamicFields} } ) {
                    if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

                        #remove leading spaces
                        $CustomerCompanyData{DynamicFields}{$Attribute} =~ s{\A\s+}{};

                        #remove trailing spaces
                        $CustomerCompanyData{DynamicFields}{$Attribute} =~ s{\s+\z}{};
                    }
                }
            }
            
            for my $Table ( @{$Object->{decode('UTF-8', 'ТабличнаяЧасть')}} ) {
                if ($Table->{decode('UTF-8', 'Имя')} eq 'systems') {
                    my %CustomerSystems;

                    for my $System ( @{$Table->{decode('UTF-8', 'Запись')}} ) {
                        my $Abbr;
                        my $Distr;
                        for my $Param ( @{$System->{decode('UTF-8', 'Свойство')}} ) {
                            if ($Param->{decode('UTF-8', 'Имя')} eq 'abbr') {
                                $Abbr = $Param->{decode('UTF-8', 'Значение')};
                            }
                            elsif ($Param->{decode('UTF-8', 'Имя')} eq 'distr') {
                                $Distr = $Param->{decode('UTF-8', 'Значение')};
                            }
                        }
                        $Distr = sprintf "%s_%06s", $Abbr, $Distr;
                            
                        $CustomerSystems{$Abbr} = $Distr;
                        my $DistrStorage = $Self->{Config}->{'DistrStorage'};
                        
                        $DistrStorage =~ s/\$1/$Distr/;
                        $DistrStorage =~ s/\$2/$CustomerCompanyData{CustomerID}/;
                
                        my $Result = `$DistrStorage`;
                        if (!$Result) {
                            my $ErrorString =  "$CustomerCompanyData{CustomerID} : ERROR : Could not save to key-value storage\n";
                            print $ErrorLog $ErrorString;
                            print $ErrorID $CustomerCompanyData{CustomerID} . "\n";
                            print $ErrorString;
                        }
                    }
            
                    my @CustomerSystemsAbbr = keys %CustomerSystems;
                    $CustomerCompanyData{DynamicFields}{MaintainedBases} = \@CustomerSystemsAbbr;

                    my $Result = $Self->_CustomerCompanyUpsert(
                        CustomerCompany  => \%CustomerCompanyData,
                        UserID           => $Param{UserID},
                    );
                    
                    if ($Result->{Success}) {
                        print "$CustomerCompanyData{CustomerID} : DONE\n";
                    }
                    else {
                        my $ErrorString =  "$CustomerCompanyData{CustomerID} : ERROR : $Result->{ErrorMessage}\n";
                        print $ErrorLog $ErrorString;
                        print $ErrorID $CustomerCompanyData{CustomerID} . "\n";
                        print $ErrorString;
                    }
                }
                
                if ($Table->{decode('UTF-8', 'Имя')} eq 'Client_Employees') {
            
                    my @Employees = @{$Table->{decode('UTF-8', 'Запись')}};
                    
                    for my $i ( 0..$#Employees ) {
                        my %CustomerUserData;
                        
                        $CustomerUserData{Source} = 'CustomerUser';
                        $CustomerUserData{UserCustomerID} = $CustomerCompanyData{CustomerID};
                        $CustomerUserData{ValidID} = 1;
                        for my $Param ( @{$Employees[$i]->{decode('UTF-8', 'Свойство')}} ) {
                            if ($Param->{decode('UTF-8', 'Имя')} eq 'name') {
                                $CustomerUserData{UserLogin} = $Param->{decode('UTF-8', 'Значение')};
                                $CustomerUserData{ID} = $CustomerUserData{UserLogin};
                                my @UserName = split( ' ', $CustomerUserData{UserLogin} );
                                $CustomerUserData{UserLastname} = $UserName[0];
                                for my $j (1..$#UserName) {
                                    $CustomerUserData{UserFirstname} .= $UserName[$j] . ' ';
                                }
                            }
                            elsif ($Param->{decode('UTF-8', 'Имя')} eq 'email') {
                                my $Email = $Param->{decode('UTF-8', 'Значение')} || '';
                                if ( $Email =~ m/[^@]+@[^@]+\.[^@]+$/ ) {
                                    $CustomerUserData{UserEmail} = $Email;
                                }
                                else {
                                    $CustomerUserData{UserEmail} = $CustomerUserData{UserLastname} . '-' . $i . '-' . $CustomerCompanyData{CustomerID} . '@noemail.ru';
                                }
                            }
                        }
                       
                        # remove leading and trailing spaces
                        for my $Attribute ( sort keys %CustomerUserData ) {
                            if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

                                #remove leading spaces
                                $CustomerUserData{$Attribute} =~ s{\A\s+}{};

                                #remove trailing spaces
                                $CustomerUserData{$Attribute} =~ s{\s+\z}{};
                            }
                        }
                        
                        my $Result = $Self->_CustomerUserUpsert(
                            CustomerUser  => \%CustomerUserData,
                            UserID           => $Param{UserID},
                        );
                    
                        if ($Result->{Success}) {
                            print "$CustomerCompanyData{CustomerID}-$CustomerUserData{UserLogin} : DONE\n";
                        }
                        else {
                            my $ErrorString =  "$CustomerCompanyData{CustomerID}-$CustomerUserData{UserLogin} : ERROR : $Result->{ErrorMessage}\n";
                            print $ErrorLog $ErrorString;
                            print $ErrorID $CustomerCompanyData{CustomerID} . "\n";
                            print $ErrorString;
                        }
                    }
                }
            }
        }
    }           
    
    close $ErrorLog;
    close $ErrorID;
    
    return {
        Success => 1,
        Data    => {
            Result => "Success",
        },
    };
}

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

=item _CustomerCompanyUpsert()

creates, or updates id already exists, a customer company with specified parameters

    my $Response = $OperationObject->_CustomerCompanyCreate(
	CustomerCompany                 => {
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
        UserID                          => 'SomeID'
    );

    returns:

    $Response = {
        Success => 1,                                                   # if everething is OK
        Data => {
            CustomerID             => 123,
            CustomerCompanyName    => 'CompanyName',
        }
    }

    $Response = {
        Success      => 0,                                              # if unexpected error
        ErrorMessage => "$Param{ErrorCode}: $Param{ErrorMessage}",
    }

=cut

sub _CustomerCompanyUpsert {
    my ( $Self, %Param ) = @_;

    my $CustomerCompany  = $Param{CustomerCompany};

    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $CustomerCompanyObject = $Kernel::OM->Get('Kernel::System::CustomerCompany');
    
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

        return {
            Success => 1,
            Data    => {
                CustomerID          => $CustomerCompany->{CustomerID},
                CustomerCompanyName => $CustomerCompany->{CustomerCompanyName},
            },
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
        my %CustomerCompanyData = $CustomerCompanyObject->CustomerCompanyGet(
            CustomerID => $Result,
        );

        if ( !IsHashRefWithData( \%CustomerCompanyData ) ) {
            return {
                Success      => 0,
                ErrorMessage => 'Could not get new customer company information, please contact the system'
                    . ' administrator',
            }
        }

        return {
            Success => 1,
            Data    => {
                CustomerID          => $Result,
                CustomerCompanyName => $CustomerCompanyData{CustomerCompanyName},
            },
        };
    }
}

=item _CustomerUserUpsert()

creates a customer user with specified parameters

    my $Response = $OperationObject->_CustomerUserUpsert(
        CustomerUser => {
            Source         => 'CustomerUser',
            UserLogin      => $Self->GetOption('new login'),
            ID             => $Self->GetOption('old login'),
            UserFirstname  => $Self->GetOption('first-name'),
            UserLastname   => $Self->GetOption('last-name'),
            UserCustomerID => $Self->GetOption('customer-id'),
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

sub _CustomerUserUpsert {
    my ( $Self, %Param ) = @_;

    my $CustomerUser  = $Param{CustomerUser};

    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');
	
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

        return {
            Success => 1,
            Data    => {
                Result => $Result,
            },
        };
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

        return {
            Success => 1,
            Data    => {
                CustomerUserLogin => $CustomerUserLogin,
            },
        };
    }
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
