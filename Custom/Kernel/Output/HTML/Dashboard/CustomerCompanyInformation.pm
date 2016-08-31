# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::Dashboard::CustomerCompanyInformation;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # get needed parameters
    for my $Needed (qw(Config Name UserID)) {
        die "Got no $Needed!" if ( !$Self->{$Needed} );
    }

    $Self->{PrefKey} = 'UserDashboardPref' . $Self->{Name} . '-Shown';

    $Self->{CacheKey} = $Self->{Name};

    return $Self;
}

sub Preferences {
    my ( $Self, %Param ) = @_;

    return;
}

sub Config {
    my ( $Self, %Param ) = @_;

    return (
        %{ $Self->{Config} },

        # caching not needed
        CacheKey => undef,
        CacheTTL => undef,
    );
}

sub Run {
    my ( $Self, %Param ) = @_;

    return if !$Param{CustomerID};

    my %CustomerCompany = $Kernel::OM->Get('Kernel::System::CustomerCompany')->CustomerCompanyGet(
        CustomerID => $Param{CustomerID},
    );

    my $CustomerCompanyConfig = $Kernel::OM->Get('Kernel::Config')->Get( $CustomerCompany{Source} || '' );
    return if ref $CustomerCompanyConfig ne 'HASH';
    return if ref $CustomerCompanyConfig->{Map} ne 'ARRAY';

    return if !%CustomerCompany;

    # get needed objects
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ValidObject  = $Kernel::OM->Get('Kernel::System::Valid');
    my $CompanyIsValid;

    # make ValidID readable
    if ( $CustomerCompany{ValidID} ) {
        my @ValidIDs = $ValidObject->ValidIDsGet();
        $CompanyIsValid = grep { $CustomerCompany{ValidID} == $_ } @ValidIDs;

        $CustomerCompany{ValidID} = $ValidObject->ValidLookup(
            ValidID => $CustomerCompany{ValidID},
        );

        $CustomerCompany{ValidID} = $LayoutObject->{LanguageObject}->Translate( $CustomerCompany{ValidID} );
    }

    ENTRY:
    for my $Entry ( @{ $CustomerCompanyConfig->{Map} } ) {
        my $Key = $Entry->[0];

        # do not show items if they're not marked as visible
        next ENTRY if !$Entry->[3];

        # do not show empty entries
        next ENTRY if !length( $CustomerCompany{$Key} );

        $LayoutObject->Block( Name => "ContentSmallCustomerCompanyInformationRow" );

        if ( $Key eq 'CustomerID' ) {
            $LayoutObject->Block(
                Name => "ContentSmallCustomerCompanyInformationRowLink",
                Data => {
                    %CustomerCompany,
                    Label => $Entry->[1],
                    Value => $CustomerCompany{$Key},
                    URL =>
                        '[% Env("Baselink") %]Action=AdminCustomerCompany;Subaction=Change;CustomerID=[% Data.CustomerID | uri %];Nav=Agent',
                    Target => '',
                },
            );

            next ENTRY;
        }

        # check if a link must be placed
        if ( $Entry->[6] ) {
            $LayoutObject->Block(
                Name => "ContentSmallCustomerCompanyInformationRowLink",
                Data => {
                    %CustomerCompany,
                    Label  => $Entry->[1],
                    Value  => $CustomerCompany{$Key},
                    URL    => $Entry->[6],
                    Target => '_blank',
                },
            );

            next ENTRY;

        }

        $LayoutObject->Block(
            Name => "ContentSmallCustomerCompanyInformationRowText",
            Data => {
                %CustomerCompany,
                Label => $Entry->[1],
                Value => $CustomerCompany{$Key},
            },
        );

        if ( $Key eq 'CustomerCompanyName' && defined $CompanyIsValid && !$CompanyIsValid ) {
            $LayoutObject->Block(
                Name => 'ContentSmallCustomerCompanyInvalid',
            );
        }
    }

    #add dynamic fields to the table
    #get needed objects
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    # get the dynamic fields for this screen
    $Self->{CustomerCompanyDynamicField} = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => [ 'CustomerCompany' ],
        FieldFilter => $ConfigObject->Get("AgentCustomerInformationCenter")->{DynamicField} || {},
    );
    #cycle through dynamic fields
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{ $Self->{CustomerCompanyDynamicField} } ) {
	next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

	my $Value = $DynamicFieldBackendObject->ValueGet(
	    DynamicFieldConfig => $DynamicFieldConfig,
	    ObjectID           => $Param{CustomerID},
	);

	# do not show the field if no value is set
	next DYNAMICFIELD if !length($Value);

	# if type is 'Dropdown' then key will be shown instead of value
	# to extract value we use PossibleValues array and passed key
	if ($DynamicFieldConfig->{FieldType} eq 'Dropdown') {
	    $Value = $DynamicFieldConfig->{Config}->{PossibleValues}->{$Value};
	}
	# if type is 'Multiselect' then values won't be shown at all
	# this is workaround to show values in one string
	elsif ($DynamicFieldConfig->{FieldType} eq 'Multiselect') {
	    my $ValueString = '';
	    for my $Field ( @{$Value} ) {
		$ValueString .= $DynamicFieldConfig->{Config}->{PossibleValues}->{$Field}." | \n";
	    }
	    $Value = $ValueString;
	}

	$LayoutObject->Block(
            Name => "ContentSmallCustomerCompanyInformationRowText",
            Data => {
                %CustomerCompany,
                Label => $DynamicFieldConfig->{Label},
                Value => $Value,
            },
        );
    }

    my $Content = $LayoutObject->Output(
        TemplateFile => 'AgentDashboardCustomerCompanyInformation',
        Data         => {
            %{ $Self->{Config} },
            Name => $Self->{Name},
            %CustomerCompany,
        },
        KeepScriptTags => $Param{AJAX},
    );

    return $Content;
}

1;
