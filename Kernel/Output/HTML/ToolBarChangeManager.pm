# --
# Kernel/Output/HTML/ToolBarChangeManager.pm
# Copyright (C) 2001-2014 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::ToolBarChangeManager;

use strict;
use warnings;

use Kernel::System::ITSMChange;

our @ObjectDependencies = (
    'Kernel::System::Cache',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get needed objects
    for (
        qw(ConfigObject LogObject DBObject TicketObject UserObject GroupObject LayoutObject UserID)
        )
    {
        $Self->{$_} = $Param{$_} || die "Got no $_!";
    }

    # create needed objects
    $Self->{ChangeObject} = Kernel::System::ITSMChange->new(%Param);

    # get the cache type and TTL (in seconds)
    $Self->{CacheType} = 'ITSMChangeManagementToolBarChangeManager' . $Self->{UserID};
    $Self->{CacheTTL}  = $Self->{ConfigObject}->Get('ITSMChange::ToolBar::CacheTTL') * 60;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # define action, group, label, image and prio
    my $Action = 'AgentITSMChangeManager';
    my $Group  = 'itsm-change-manager';
    my $Icon   = $Param{Config}->{Icon};

    # do not show icon if frontend module is not registered
    return if !$Self->{ConfigObject}->Get('Frontend::Module')->{$Action};

    # get config of frontend module
    my $Config = $Self->{ConfigObject}->Get("ITSMChange::Frontend::$Action");

    # get the group id
    my $GroupID = $Self->{GroupObject}->GroupLookup( Group => $Group );

    # deny access, when the group is not found
    return if !$GroupID;

    # get user groups, where the user has the appropriate privilege
    my %Groups = $Self->{GroupObject}->GroupMemberList(
        UserID => $Self->{UserID},
        Type   => $Config->{Permission},
        Result => 'HASH',
    );

    # deny access if the agent doesn't have the appropriate type in the appropriate group
    return if !$Groups{$GroupID};

    # get the number of viewable changes
    my $Count = 0;
    if ( $Config->{'Filter::ChangeStates'} && @{ $Config->{'Filter::ChangeStates'} } ) {

        # remove empty change states
        my @ChangeStates;
        CHANGESTATE:
        for my $ChangeState ( @{ $Config->{'Filter::ChangeStates'} } ) {
            next CHANGESTATE if !$ChangeState;
            push @ChangeStates, $ChangeState;
        }

        # check cache
        my $CacheKey = join ',', sort ChangeStates;
        my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
            Type => $Self->{CacheType},
            Key  => $CacheKey,
        );

        if ( defined $Cache ) {
            $Count = $Cache;
        }
        else {

            # count the number of viewable changes
            $Count = $Self->{ChangeObject}->ChangeSearch(
                ChangeManagerIDs => [ $Self->{UserID} ],
                ChangeStates     => \@ChangeStates,
                Limit            => 1000,
                Result           => 'COUNT',
                MirrorDB         => 1,
                UserID           => $Self->{UserID},
            );

            # set cache
            $Kernel::OM->Get('Kernel::System::Cache')->Set(
                Type  => $Self->{CacheType},
                Key   => $CacheKey,
                Value => $Count,
                TTL   => $Self->{CacheTTL},
            );
        }
    }

    # get ToolBar object parameters
    my $Class = $Param{Config}->{CssClass};
    my $Text  = $Self->{LayoutObject}->{LanguageObject}->Translate('Change Manager');

    # set ToolBar object
    my $URL      = $Self->{LayoutObject}->{Baselink};
    my $Priority = $Param{Config}->{Priority};
    my %Return;
    if ($Count) {
        $Return{$Priority} = {
            Block       => 'ToolBarItem',
            Description => $Text,
            Count       => $Count,
            Class       => $Class,
            Icon        => $Icon,
            Link        => $URL . 'Action=' . $Action,
            AccessKey   => '',
        };
    }

    return %Return;
}

1;
