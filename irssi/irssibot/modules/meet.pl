#!/usr/bin/perl -w
# CMDS meet

my $cmd = $$irc_event{cmd};
my $args = $$irc_event{args};

return reply("you lack permission.") if (not perms("admin", "meet", "merge"));

my $meet_nick = $args; $meet_nick =~ s/\s+$//; $meet_nick =~ s/^\s+//;
return reply("function !meet requires a nick as argument.") if ($meet_nick eq "");

foreach my $channel (Irssi::channels()) {
    next if ($$channel{name} ne $$irc_event{target});
    foreach my $nick ($channel->nicks()) {
        next if ($nick->{nick} eq $channel->{ownnick}->{nick});
        if ($nick->{nick} =~ m#^$meet_nick$#i) {
            my $tmp_user_info = $$state{dbh}->selectrow_hashref("SELECT u.* FROM ib_users u, ib_hostmasks h WHERE u.id = h.users_id AND h.hostmask = ?", undef, $nick->{host});
            if (exists $$tmp_user_info{ircnick}) {
                public("Hostmask '$nick->{host}' for nick '$nick->{nick}' matches registered user '$$tmp_user_info{ircnick}'.");
                return;
            }

            $tmp_user_info = $$state{dbh}->selectrow_hashref("SELECT * FROM ib_users WHERE ircnick = ?", undef, $nick->{nick});
            if (exists $$tmp_user_info{ircnick}) {
                reply("Nickname '".$nick->{nick}."' is already a registered user.");
                return;
            }

            $$state{dbh}->do("INSERT INTO ib_users (ircnick, insert_time) VALUES (?, NOW())", undef, $nick->{nick});
            ($tmp_user_info) = $$state{dbh}->selectrow_array("SELECT id FROM ib_users WHERE ircnick = ?", undef, $nick->{nick});
            msg("New user with users_id '$tmp_user_info', '$nick->{nick}', '$nick->{host}'");
            $$state{dbh}->do("INSERT INTO ib_hostmasks (users_id, hostmask) VALUES (?, ?)", undef, $tmp_user_info, $nick->{host});
            $$state{dbh}->do("INSERT INTO ib_perms (users_id, permission) VALUES (?, 'user')", undef, $tmp_user_info);

            public("Added to database '$nick->{nick}' at '$nick->{host}'.");
            return;
        }
    }

}

public("No nick '$meet_nick' was found on channel '$$irc_event{target}'.");
return;
