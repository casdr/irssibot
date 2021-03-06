#!/usr/bin/perl -w
# CMDS message_public
# CMDS karma setkarma set-karma
# CMDS who-karma-up who-up karma-who-up karma-whoup
# CMDS who-karma-down who-down karma-who-down karma-whodown
# CMDS wku why-karma-up why-up karma-why-up karma-whyup
# CMDS wkd why-karma-down why-down karma-why-down karma-whydown
# CMDS goodness badness
# CMDS fans haters

return if (not perms("user"));

my $msg = $$irc_event{msg};

# Since this binds to CMDS message_public, ensure the event was a
# command to the bot by requiring the bot_triggerre(gexp) to
# match the irc event data.
return if $msg !~ $$state{bot_triggerre};
$msg =~ s#$$state{bot_triggerre}##;


# !quota <id>++
# karma up/downs for quotes is handled by quotes.pl
return if $msg =~ m#^quote\s*\d+\s*(?:\+\+|\-\-)#;


if ($$irc_event{trigger} eq "module_command") {
    my @events = ( $$irc_event{msg} );
    if ($$irc_event{cmd} =~ /^wk([ud])/) {
        public($$irc_event{cmd} . " is ambiguous. showing both why and who.");
        @events = (
            'why-karma-' . ($1 eq'u'?'up':'down') . " " . $$irc_event{args},
            'who-karma-' . ($1 eq'u'?'up':'down') . " " . $$irc_event{args},

        );

    }

    foreach my $event (@events) {
        if ($event =~ /^(?:karma-why|why-karma|why)\-?(up|down)\s*(.*)/) {
            my $direction = $1;
            my $item = $2;
            $direction = "up" if $direction =~ m#^u#i;
            $direction = "down" if $direction =~ m#^d#i;
            next if (not defined $item or $item eq "");

            my $karma_item = $$state{dbh}->selectrow_hashref("
                SELECT * FROM ib_karma WHERE item = ? AND channel = ?",
                undef,
                $item, $$irc_event{channel}

            );

            my @reasons = @{$$state{dbh}->selectcol_arrayref("
                SELECT reason FROM ib_karma_why WHERE
                    karma_id = ? AND direction = ? AND channel = ?
                ORDER BY update_time DESC
                LIMIT 10",
                undef,
                $$karma_item{id}, $direction, $$irc_event{channel}

            )};

            my $c = scalar(@reasons);
            if ($c) {
                public("$c most recent reason(s) for karma $direction: " . join(" .. ", @reasons));

            } else {
                public("no reasons were given for karma $direction");

            }


        } elsif ($event =~ /^(?:karma-who|who-karma|who)\-?(up|down)\s*(.*)/) {
            my $direction = $1;
            my $item = $2;
            $direction = "up" if $direction =~ m#^u#i;
            $direction = "down" if $direction =~ m#^d#i;
            next if (not defined $item or $item eq "");

            my $karma_item = $$state{dbh}->selectrow_hashref("
                SELECT * FROM ib_karma WHERE item = ? AND channel = ?",
                undef,
                $item, $$irc_event{channel}

            );
            
            my $ret = undef;
            my $sth = $$state{dbh}->prepare(
               "SELECT u.ircnick, kwho.amount, k.item
                FROM ib_users u, ib_karma_who kwho, ib_karma k
                WHERE
                    u.id = kwho.users_id
                AND kwho.karma_id = ?
                AND k.id = ?");
            $sth->execute($$karma_item{id}, $$karma_item{id});
            while (my $row = $sth->fetchrow_hashref()) {
                $ret = defined $ret ? $ret . " .. $$row{ircnick}($$row{amount})" : "$$row{ircnick}($$row{amount})";

            }

            public($ret);

        }

    }


    if ($msg =~ /^(?:set\-?karma)\s+(.+?)\s+([-0-9]+)/) {
        my $item = $1;
        my $karma = $2;
        return reply("nope.") if not perms('admin');

        $$state{dbh}->do("INSERT INTO ib_karma (item, channel, karma) VALUES (?, ?, ?)
                            ON DUPLICATE KEY UPDATE karma = ?",
            undef, $item, $$irc_event{channel}, $karma, $karma);
        return reply("ok.") unless $$state{dbh}->errstr();
        return reply("fail: " . $$state{dbh}->errstr());

    } elsif ($msg =~ /^(fans|haters)\s*(.*)$/) {
        my $orig_direction = $1; 
        my $direction = $orig_direction; # duplicate for display purposes
        my $item = $2;

        $direction = "up" if $direction eq "fans";
        $direction = "down" if $direction eq "haters";
        $orig_direction = ucfirst(lc($orig_direction));
 
        my $karma_item = $$state{dbh}->selectrow_hashref("
            SELECT * FROM ib_karma WHERE item = ? AND channel = ?",
            undef,
            $item, $$irc_event{channel}

        );

        return public("No such karma item, '$item'.") if not defined $$karma_item{item};

        my $sth = $$state{dbh}->prepare(
            "SELECT kw.id AS ib_karma_who_id,
                    kw.amount AS amount,
                    u.id AS ib_users_id,
                    u.*
            FROM ib_karma_who kw, ib_users u
            WHERE u.id = kw.users_id
                AND karma_id = ?
                AND direction = ?
            ORDER BY amount DESC LIMIT 10"

        );

        $sth->execute($$karma_item{id}, $direction);

        my $ret = undef;
        while (my $row = $sth->fetchrow_hashref()) {
            $ret = defined $ret ? $ret . " .. $$row{ircnick}($$row{amount})" : "$$row{ircnick}($$row{amount})";

        }

        if (defined $ret) {
            return public("$orig_direction of '$$karma_item{item}' are $ret");

        } else {
            return public("No " . lc($orig_direction) . " for '$$karma_item{item}' are known.");

        }


    } elsif ($msg =~ /^(good|bad)ness\s*$/) {
        my $direction = $1;
        my $sql_direction = "";
        $sql_direction = "ASC" if $direction eq "bad";
        $sql_direction = "DESC" if $direction eq "good";
 
        my $ret = undef;
        my $sth = $$state{dbh}->prepare("SELECT item, karma FROM ib_karma WHERE channel = ? ORDER BY karma $sql_direction LIMIT 10");
        $sth->execute($$irc_event{channel});
        while (my $row = $sth->fetchrow_hashref()) {
            $ret = defined $ret ? $ret . " .. $$row{item}($$row{karma})" : "$$row{item}($$row{karma})";

        }

        return public("Karma ${direction}ness: " . $ret);


    } elsif ($msg =~ /^karma\s+(.*)/) {
        my $item = $1;
        return if ((not defined $item) or ($item eq ""));
        my $karma_item = $$state{dbh}->selectrow_hashref("
            SELECT * FROM ib_karma WHERE item = ? AND channel = ?",
             undef,
            $item, $$irc_event{channel}

        );

        if (defined $$karma_item{karma}) {
            return reply("karma for '$item' is $$karma_item{karma}.");

        }

        return reply("karma for '$item' is neutral.");

    }


    return;
} 


if ($msg =~ /^(.+?)\s*([\+\-]{2})(?:\s*#\s*(.*))?/) {
    my $item = $1;
    my $direction = $2;
    my $reason = $3;

    my $update_sql = "";
    my $initialvalue = 0;
    if ($direction eq "++") {
        $direction = "up";
        $update_sql = "karma = karma + 1";
        $initialvalue = 1;

    } elsif ($direction eq "--") {
        $direction = "down";
        $update_sql = "karma = karma - 1";
        $initialvalue = -1;

    }

    my $rv = $$state{dbh}->do("
        INSERT INTO ib_karma (item, karma, channel)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY
            UPDATE $update_sql",
        undef,
        $item, $initialvalue, $$irc_event{channel}

    );

    my $karma_item = $$state{dbh}->selectrow_hashref("
        SELECT * FROM ib_karma WHERE item = ? AND channel = ?",
        undef,
        $item, $$irc_event{channel}

    );

    $$state{dbh}->do("
        INSERT INTO ib_karma_who (karma_id, users_id, direction, amount)
        VALUES (?, ?, ?, 1)
        ON DUPLICATE KEY
            UPDATE amount = amount + 1",
        undef,
        $$karma_item{id},
        $$state{user_info}{id},
        $direction);

    if (defined $reason and $reason ne "") {
        my $rv = $$state{dbh}->do("
            INSERT INTO ib_karma_why (karma_id, direction, reason, channel)
            VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY
                UPDATE update_time = NOW()",
            undef,
            $$karma_item{id}, $direction, $reason, $$irc_event{channel}

        );

        reply("karma for '$item' is now $$karma_item{karma} - '$reason'");

    } else {

        reply("karma for '$item' is now $$karma_item{karma}");

    }


}
